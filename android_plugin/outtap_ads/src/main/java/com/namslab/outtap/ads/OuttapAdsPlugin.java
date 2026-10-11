package com.namslab.outtap.ads;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.Network;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdListener;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.AdSize;
import com.google.android.gms.ads.AdValue;
import com.google.android.gms.ads.AgeRestrictedTreatment;
import com.google.android.gms.ads.AdView;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.RequestConfiguration;
import com.google.android.gms.ads.ResponseInfo;
import com.google.android.gms.ads.initialization.AdapterStatus;
import com.google.android.gms.ads.interstitial.InterstitialAd;
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;
import com.google.android.ump.ConsentDebugSettings;
import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.FormError;
import com.google.android.ump.UserMessagingPlatform;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONException;
import org.json.JSONObject;

import java.security.MessageDigest;
import java.util.Collections;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Outtap's bridge to the Google Mobile Ads SDK (play-services-ads) and the User Messaging
 * Platform. It holds no product policy: GDScript (AdsManager) decides when to load and show.
 *
 * Threading: methods are invoked by Godot on its render thread. Every SDK call is posted to the
 * Android main thread. Results go back through emitSignal, which Godot queues onto the render
 * thread, so GDScript always handles them on its own thread.
 *
 * Each load/show carries a request id from GDScript. A loaded ad is kept only while its id is
 * still the pending one; a shown ad object is released immediately and never shown twice.
 */
public class OuttapAdsPlugin extends GodotPlugin {
	private static final String TAG = "OuttapAds";
	private static final String PLUGIN_VERSION = "1.0.0";
	private static final String SDK_FAMILY = "play-services-ads (Google Mobile Ads SDK, legacy API)";
	private static final String UMP_VERSION = BuildConfig.UMP_VERSION;
	private static final String GMA_VERSION = BuildConfig.GMA_VERSION;

	private final Handler main = new Handler(Looper.getMainLooper());
	private final Object lock = new Object();
	private final AtomicBoolean sdkInitStarted = new AtomicBoolean(false);

	private ConsentInformation consentInformation;
	private volatile boolean resumed = false;
	private boolean testMode = false;
	private String maxAdContentRating = RequestConfiguration.MAX_AD_CONTENT_RATING_PG;
	// GMA 25 replaced the separate child/under-age tags with one age-restricted treatment.
	private AgeRestrictedTreatment ageTreatment = AgeRestrictedTreatment.UNSPECIFIED;

	// Full-screen slots, guarded by `lock`.
	private InterstitialAd interstitial;
	private int interstitialId = -1;
	private int interstitialPending = -1;
	private RewardedAd rewarded;
	private int rewardedId = -1;
	private int rewardedPending = -1;

	// Banner
	private FrameLayout bannerContainer;
	private AdView bannerView;
	private String bannerUnit = "";
	private volatile int bannerRequestId = -1;
	private boolean bannerWanted = false;
	private int navigationInset = 0;

	private ConnectivityManager.NetworkCallback networkCallback;

	public OuttapAdsPlugin(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "OuttapAds";
	}

	@NonNull
	@Override
	public Set<SignalInfo> getPluginSignals() {
		Set<SignalInfo> signals = new HashSet<>();
		signals.add(new SignalInfo("ads_event", String.class, String.class));
		return signals;
	}

	// ---------------------------------------------------------------------------------------------
	// Lifecycle

	@Override
	public View onMainCreate(Activity activity) {
		consentInformation = UserMessagingPlatform.getConsentInformation(activity);
		bannerContainer = new FrameLayout(activity);
		bannerContainer.setLayoutParams(new FrameLayout.LayoutParams(
				FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
		// The container never consumes touches; only the AdView inside it is interactive.
		bannerContainer.setClickable(false);
		bannerContainer.setFocusable(false);
		ViewCompat.setOnApplyWindowInsetsListener(bannerContainer, (view, insets) -> {
			Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
			navigationInset = bars.bottom;
			placeBanner();
			return insets;
		});
		registerNetworkCallback(activity);
		return bannerContainer;
	}

	@Override
	public void onMainResume() {
		resumed = true;
		if (bannerView != null && bannerWanted) {
			bannerView.resume();
		}
		emit("activity_state", json("resumed", true));
	}

	@Override
	public void onMainPause() {
		resumed = false;
		if (bannerView != null) {
			bannerView.pause();
		}
		emit("activity_state", json("resumed", false));
	}

	@Override
	public void onMainDestroy() {
		if (bannerView != null) {
			bannerView.destroy();
			bannerView = null;
		}
		unregisterNetworkCallback();
	}

	// ---------------------------------------------------------------------------------------------
	// Info / configuration

	@UsedByGodot
	public String getInfo() {
		JSONObject info = new JSONObject();
		try {
			info.put("plugin_version", PLUGIN_VERSION);
			info.put("sdk_family", SDK_FAMILY);
			info.put("sdk_version", MobileAds.getVersion().toString());
			info.put("gma_dependency", GMA_VERSION);
			info.put("ump_version", UMP_VERSION);
			info.put("manifest_app_id", manifestAppId());
			info.put("debuggable", isDebuggable());
		} catch (JSONException ignored) {
		}
		return info.toString();
	}

	@UsedByGodot
	public void configure(String config) {
		try {
			JSONObject c = new JSONObject(config);
			testMode = c.optBoolean("test_mode", false);
			maxAdContentRating = ratingConstant(c.optString("max_ad_content_rating", "PG"));
			if (c.optInt("child_directed", -1) == 1) {
				ageTreatment = AgeRestrictedTreatment.CHILD;
			} else if (c.optInt("under_age_of_consent", -1) == 1) {
				ageTreatment = AgeRestrictedTreatment.TEEN;
			} else {
				ageTreatment = AgeRestrictedTreatment.UNSPECIFIED;
			}
		} catch (JSONException e) {
			Log.w(TAG, "configure: bad json", e);
		}
	}

	// ---------------------------------------------------------------------------------------------
	// Consent (UMP)

	@UsedByGodot
	public void requestConsentInfoUpdate(int debugGeography) {
		main.post(() -> {
			Activity activity = getActivity();
			if (activity == null || consentInformation == null) {
				emit("consent_info_failed", errorJson(-1, "activity_unavailable"));
				return;
			}
			ConsentRequestParameters.Builder params = new ConsentRequestParameters.Builder();
			if (testMode && isDebuggable() && debugGeography > 0) {
				ConsentDebugSettings debug = new ConsentDebugSettings.Builder(activity)
						.setDebugGeography(debugGeography == 1
								? ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA
								: ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_NOT_EEA)
						.addTestDeviceHashedId(hashedDeviceId(activity))
						.build();
				params.setConsentDebugSettings(debug);
			}
			consentInformation.requestConsentInfoUpdate(activity, params.build(),
					() -> emit("consent_info_updated", consentJson(null)),
					(FormError error) -> {
						JSONObject data = consentJson(error);
						emit("consent_info_failed", data);
					});
		});
	}

	@UsedByGodot
	public boolean canRequestAds() {
		return consentInformation != null && consentInformation.canRequestAds();
	}

	@UsedByGodot
	public boolean isPrivacyOptionsRequired() {
		return consentInformation != null && consentInformation.getPrivacyOptionsRequirementStatus()
				== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED;
	}

	@UsedByGodot
	public void loadAndShowConsentFormIfRequired() {
		main.post(() -> {
			Activity activity = getActivity();
			if (activity == null) {
				emit("consent_form_dismissed", consentJson(null));
				return;
			}
			UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity,
					(FormError error) -> emit("consent_form_dismissed", consentJson(error)));
		});
	}

	@UsedByGodot
	public void showPrivacyOptionsForm() {
		main.post(() -> {
			Activity activity = getActivity();
			if (activity == null) {
				emit("privacy_form_dismissed", consentJson(null));
				return;
			}
			UserMessagingPlatform.showPrivacyOptionsForm(activity,
					(FormError error) -> emit("privacy_form_dismissed", consentJson(error)));
		});
	}

	@UsedByGodot
	public void resetConsent() {
		if (isDebuggable() && consentInformation != null) {
			consentInformation.reset();
		}
	}

	// ---------------------------------------------------------------------------------------------
	// SDK initialization

	@UsedByGodot
	public void initializeSdk() {
		if (!sdkInitStarted.compareAndSet(false, true)) {
			return; // previous-session and this-session consent paths may both ask; run once
		}
		Activity activity = getActivity();
		if (activity == null) {
			sdkInitStarted.set(false);
			return;
		}
		Context app = activity.getApplicationContext();
		RequestConfiguration.Builder request = MobileAds.getRequestConfiguration().toBuilder()
				.setMaxAdContentRating(maxAdContentRating)
				.setAgeRestrictedTreatment(ageTreatment);
		if (testMode && isDebuggable()) {
			// Registers this device as a test device so Ad Inspector and debug features work.
			request.setTestDeviceIds(Collections.singletonList(hashedDeviceId(activity)));
		}
		MobileAds.setRequestConfiguration(request.build());
		final long started = System.currentTimeMillis();
		new Thread(() -> MobileAds.initialize(app, status -> {
			JSONObject data = new JSONObject();
			JSONObject adapters = new JSONObject();
			try {
				for (Map.Entry<String, AdapterStatus> entry : status.getAdapterStatusMap().entrySet()) {
					adapters.put(entry.getKey(), entry.getValue().getInitializationState().name());
				}
				data.put("adapters", adapters);
				data.put("latency_ms", System.currentTimeMillis() - started);
			} catch (JSONException ignored) {
			}
			emit("sdk_initialized", data);
		}), "OuttapAdsInit").start();
	}

	// ---------------------------------------------------------------------------------------------
	// Full-screen ads

	@UsedByGodot
	public void loadAd(String format, int requestId, String unitId) {
		synchronized (lock) {
			if ("interstitial".equals(format)) {
				interstitialPending = requestId;
			} else {
				rewardedPending = requestId;
			}
		}
		main.post(() -> {
			Activity activity = getActivity();
			if (activity == null) {
				emit("ad_load_failed", loadFailure(format, requestId, -1, "outtap", "activity_unavailable", null));
				return;
			}
			AdRequest request = new AdRequest.Builder().build();
			if ("interstitial".equals(format)) {
				InterstitialAd.load(activity, unitId, request, new InterstitialAdLoadCallback() {
					@Override
					public void onAdLoaded(@NonNull InterstitialAd ad) {
						boolean keep;
						synchronized (lock) {
							keep = interstitialPending == requestId;
							if (keep) {
								interstitial = ad;
								interstitialId = requestId;
								interstitialPending = -1;
							}
						}
						emit("ad_loaded", loaded(format, requestId, ad.getResponseInfo(), keep));
					}

					@Override
					public void onAdFailedToLoad(@NonNull LoadAdError error) {
						synchronized (lock) {
							if (interstitialPending == requestId) {
								interstitialPending = -1;
							}
						}
						emit("ad_load_failed", loadFailure(format, requestId, error.getCode(), error.getDomain(), error.getMessage(), error.getResponseInfo()));
					}
				});
			} else {
				RewardedAd.load(activity, unitId, request, new RewardedAdLoadCallback() {
					@Override
					public void onAdLoaded(@NonNull RewardedAd ad) {
						boolean keep;
						synchronized (lock) {
							keep = rewardedPending == requestId;
							if (keep) {
								rewarded = ad;
								rewardedId = requestId;
								rewardedPending = -1;
							}
						}
						emit("ad_loaded", loaded(format, requestId, ad.getResponseInfo(), keep));
					}

					@Override
					public void onAdFailedToLoad(@NonNull LoadAdError error) {
						synchronized (lock) {
							if (rewardedPending == requestId) {
								rewardedPending = -1;
							}
						}
						emit("ad_load_failed", loadFailure(format, requestId, error.getCode(), error.getDomain(), error.getMessage(), error.getResponseInfo()));
					}
				});
			}
		});
	}

	/** Returns true only when the matching cached ad exists and an activity can host it. */
	@UsedByGodot
	public boolean showAd(String format, int requestId) {
		final Activity activity = getActivity();
		if (activity == null || activity.isFinishing()) {
			return false;
		}
		final InterstitialAd showInterstitial;
		final RewardedAd showRewarded;
		synchronized (lock) {
			if ("interstitial".equals(format)) {
				if (interstitial == null || interstitialId != requestId) {
					return false;
				}
				showInterstitial = interstitial;
				showRewarded = null;
				interstitial = null; // a shown object is never reused
				interstitialId = -1;
			} else {
				if (rewarded == null || rewardedId != requestId) {
					return false;
				}
				showRewarded = rewarded;
				showInterstitial = null;
				rewarded = null;
				rewardedId = -1;
			}
		}
		FullScreenContentCallback callback = new FullScreenContentCallback() {
			@Override
			public void onAdShowedFullScreenContent() {
				emit("ad_showed", ids(format, requestId));
			}

			@Override
			public void onAdImpression() {
				emit("ad_impression", ids(format, requestId));
			}

			@Override
			public void onAdClicked() {
				emit("ad_clicked", ids(format, requestId));
			}

			@Override
			public void onAdDismissedFullScreenContent() {
				emit("ad_dismissed", ids(format, requestId));
			}

			@Override
			public void onAdFailedToShowFullScreenContent(@NonNull AdError error) {
				JSONObject data = ids(format, requestId);
				put(data, "domain", error.getDomain());
				put(data, "code", error.getCode());
				put(data, "message", error.getMessage());
				emit("ad_show_failed", data);
			}
		};
		main.post(() -> {
			if (activity.isFinishing() || activity.isDestroyed()) {
				JSONObject data = ids(format, requestId);
				put(data, "domain", "outtap");
				put(data, "code", -1);
				put(data, "message", "activity_unavailable");
				emit("ad_show_failed", data);
				return;
			}
			if (showInterstitial != null) {
				showInterstitial.setFullScreenContentCallback(callback);
				showInterstitial.setOnPaidEventListener(value -> emit("ad_paid", paid(format, requestId, value)));
				showInterstitial.show(activity);
			} else {
				showRewarded.setFullScreenContentCallback(callback);
				showRewarded.setOnPaidEventListener(value -> emit("ad_paid", paid(format, requestId, value)));
				showRewarded.show(activity, reward -> {
					JSONObject data = ids(format, requestId);
					put(data, "type", reward.getType());
					put(data, "amount", reward.getAmount());
					emit("reward_earned", data);
				});
			}
		});
		return true;
	}

	/** Drops a cached or in-flight ad so a late result can never be shown. */
	@UsedByGodot
	public void discardAd(String format, int requestId) {
		synchronized (lock) {
			if ("interstitial".equals(format)) {
				if (interstitialId == requestId) {
					interstitial = null;
					interstitialId = -1;
				}
				if (interstitialPending == requestId) {
					interstitialPending = -1;
				}
			} else {
				if (rewardedId == requestId) {
					rewarded = null;
					rewardedId = -1;
				}
				if (rewardedPending == requestId) {
					rewardedPending = -1;
				}
			}
		}
	}

	// ---------------------------------------------------------------------------------------------
	// Anchored adaptive banner

	@UsedByGodot
	public void bannerConfigure(String unitId) {
		bannerUnit = unitId;
	}

	@UsedByGodot
	public void bannerLoad(int requestId) {
		bannerRequestId = requestId;
		main.post(() -> {
			Activity activity = getActivity();
			if (activity == null || bannerContainer == null || bannerUnit.isEmpty()) {
				emit("banner_failed", loadFailure("banner", requestId, -1, "outtap", "banner_unavailable", null));
				return;
			}
			if (bannerView == null) {
				bannerView = new AdView(activity);
				bannerView.setAdUnitId(bannerUnit);
				bannerView.setAdSize(adaptiveSize(activity));
				bannerView.setVisibility(View.GONE);
				bannerView.setAdListener(new AdListener() {
					@Override
					public void onAdLoaded() {
						AdView view = bannerView;
						if (view == null) {
							return;
						}
						JSONObject data = loaded("banner", bannerRequestId, view.getResponseInfo(), true);
						AdSize size = view.getAdSize();
						if (size != null) {
							put(data, "height_px", size.getHeightInPixels(activity));
							put(data, "width_px", size.getWidthInPixels(activity));
						}
						emit("banner_loaded", data);
					}

					@Override
					public void onAdFailedToLoad(@NonNull LoadAdError error) {
						emit("banner_failed", loadFailure("banner", bannerRequestId, error.getCode(), error.getDomain(), error.getMessage(), error.getResponseInfo()));
					}

					@Override
					public void onAdImpression() {
						emit("banner_impression", ids("banner", bannerRequestId));
					}
				});
				bannerView.setOnPaidEventListener(value -> emit("banner_paid", paid("banner", bannerRequestId, value)));
				FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
						FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
						Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
				bannerContainer.addView(bannerView, params);
				placeBanner();
			}
			bannerView.loadAd(new AdRequest.Builder().build());
		});
	}

	@UsedByGodot
	public void bannerSetVisible(boolean visible) {
		main.post(() -> {
			bannerWanted = visible;
			if (bannerView == null) {
				return;
			}
			bannerView.setVisibility(visible ? View.VISIBLE : View.GONE);
			// Hidden banners stop refreshing; nothing reloads while hidden.
			if (visible) {
				bannerView.resume();
			} else {
				bannerView.pause();
			}
		});
	}

	@UsedByGodot
	public void bannerDestroy() {
		main.post(() -> {
			if (bannerView != null) {
				bannerContainer.removeView(bannerView);
				bannerView.destroy();
				bannerView = null;
			}
		});
	}

	private void placeBanner() {
		if (bannerView == null) {
			return;
		}
		FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) bannerView.getLayoutParams();
		if (params != null) {
			params.bottomMargin = navigationInset;
			bannerView.setLayoutParams(params);
		}
	}

	/** Anchored adaptive size from the real usable width (window minus side insets/cutouts). */
	private AdSize adaptiveSize(Activity activity) {
		DisplayMetrics metrics = activity.getResources().getDisplayMetrics();
		int widthPx = bannerContainer != null && bannerContainer.getWidth() > 0 ? bannerContainer.getWidth() : metrics.widthPixels;
		WindowInsetsCompat insets = ViewCompat.getRootWindowInsets(activity.getWindow().getDecorView());
		if (insets != null) {
			Insets sides = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
			widthPx -= sides.left + sides.right;
		}
		int widthDp = (int) (widthPx / metrics.density);
		return AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(activity, widthDp);
	}

	// ---------------------------------------------------------------------------------------------
	// Tools / state

	@UsedByGodot
	public boolean openAdInspector() {
		Activity activity = getActivity();
		if (activity == null) {
			return false;
		}
		main.post(() -> MobileAds.openAdInspector(activity, error -> {
			JSONObject data = new JSONObject();
			if (error != null) {
				put(data, "code", error.getCode());
				put(data, "message", error.getMessage());
			}
			emit("ad_inspector_closed", data);
		}));
		return true;
	}

	@UsedByGodot
	public boolean isActivityResumed() {
		return resumed;
	}

	@UsedByGodot
	public String nativeStatus() {
		JSONObject s = new JSONObject();
		synchronized (lock) {
			put(s, "interstitial_cached_id", interstitialId);
			put(s, "interstitial_pending_id", interstitialPending);
			put(s, "rewarded_cached_id", rewardedId);
			put(s, "rewarded_pending_id", rewardedPending);
		}
		put(s, "activity_resumed", resumed);
		put(s, "sdk_init_started", sdkInitStarted.get());
		put(s, "banner_created", bannerView != null);
		put(s, "banner_request_id", bannerRequestId);
		if (consentInformation != null) {
			put(s, "consent_status", consentInformation.getConsentStatus());
			put(s, "can_request_ads", consentInformation.canRequestAds());
			put(s, "privacy_required", isPrivacyOptionsRequired());
		}
		return s.toString();
	}

	// ---------------------------------------------------------------------------------------------
	// Network

	private void registerNetworkCallback(Context context) {
		try {
			ConnectivityManager manager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
			if (manager == null) {
				return;
			}
			networkCallback = new ConnectivityManager.NetworkCallback() {
				@Override
				public void onAvailable(@NonNull Network network) {
					emit("network_state", json("available", true));
				}

				@Override
				public void onLost(@NonNull Network network) {
					emit("network_state", json("available", manager.getActiveNetwork() != null));
				}
			};
			manager.registerDefaultNetworkCallback(networkCallback);
		} catch (SecurityException e) {
			Log.w(TAG, "network callback unavailable", e);
		}
	}

	private void unregisterNetworkCallback() {
		Activity activity = getActivity();
		if (networkCallback == null || activity == null) {
			return;
		}
		try {
			ConnectivityManager manager = (ConnectivityManager) activity.getSystemService(Context.CONNECTIVITY_SERVICE);
			if (manager != null) {
				manager.unregisterNetworkCallback(networkCallback);
			}
		} catch (IllegalArgumentException ignored) {
		}
		networkCallback = null;
	}

	// ---------------------------------------------------------------------------------------------
	// Helpers

	private void emit(String name, JSONObject data) {
		emitSignal("ads_event", name, data.toString());
	}

	private JSONObject consentJson(FormError error) {
		JSONObject data = new JSONObject();
		if (consentInformation != null) {
			put(data, "can_request_ads", consentInformation.canRequestAds());
			put(data, "consent_status", consentInformation.getConsentStatus());
			put(data, "privacy_required", isPrivacyOptionsRequired());
		}
		if (error != null) {
			put(data, "code", error.getErrorCode());
			put(data, "message", error.getMessage());
		}
		return data;
	}

	private static JSONObject errorJson(int code, String message) {
		JSONObject data = new JSONObject();
		put(data, "code", code);
		put(data, "message", message);
		return data;
	}

	private static JSONObject ids(String format, int requestId) {
		JSONObject data = new JSONObject();
		put(data, "format", format);
		put(data, "request_id", requestId);
		return data;
	}

	private static JSONObject loaded(String format, int requestId, ResponseInfo info, boolean kept) {
		JSONObject data = ids(format, requestId);
		put(data, "kept", kept);
		addResponse(data, info);
		return data;
	}

	private static JSONObject loadFailure(String format, int requestId, int code, String domain, String message, ResponseInfo info) {
		JSONObject data = ids(format, requestId);
		put(data, "code", code);
		put(data, "domain", domain);
		put(data, "message", message);
		addResponse(data, info);
		return data;
	}

	private static void addResponse(JSONObject data, ResponseInfo info) {
		if (info == null) {
			return;
		}
		put(data, "response_id", info.getResponseId() == null ? "" : info.getResponseId());
		JSONObject response = new JSONObject();
		put(response, "adapter", info.getMediationAdapterClassName() == null ? "" : info.getMediationAdapterClassName());
		put(response, "adapter_responses", info.getAdapterResponses().size());
		Bundle extras = info.getResponseExtras();
		put(response, "has_extras", extras != null && !extras.isEmpty());
		put(data, "response_info", response);
	}

	private static JSONObject paid(String format, int requestId, AdValue value) {
		JSONObject data = ids(format, requestId);
		put(data, "value_micros", value.getValueMicros());
		put(data, "currency", value.getCurrencyCode());
		put(data, "precision", value.getPrecisionType());
		return data;
	}

	private static JSONObject json(String key, Object value) {
		JSONObject data = new JSONObject();
		put(data, key, value);
		return data;
	}

	private static void put(JSONObject data, String key, Object value) {
		try {
			data.put(key, value);
		} catch (JSONException ignored) {
		}
	}

	private String manifestAppId() {
		Activity activity = getActivity();
		if (activity == null) {
			return "";
		}
		try {
			ApplicationInfo info = activity.getPackageManager().getApplicationInfo(activity.getPackageName(), PackageManager.GET_META_DATA);
			Bundle meta = info.metaData;
			return meta == null ? "" : meta.getString("com.google.android.gms.ads.APPLICATION_ID", "");
		} catch (PackageManager.NameNotFoundException e) {
			return "";
		}
	}

	private boolean isDebuggable() {
		Activity activity = getActivity();
		return activity != null && (activity.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
	}

	/** Test-device hash used by the SDK (MD5 of ANDROID_ID). Only read in debuggable test builds. */
	@SuppressLint("HardwareIds")
	private static String hashedDeviceId(Context context) {
		try {
			String androidId = Settings.Secure.getString(context.getContentResolver(), Settings.Secure.ANDROID_ID);
			MessageDigest digest = MessageDigest.getInstance("MD5");
			byte[] hash = digest.digest(androidId.getBytes());
			StringBuilder hex = new StringBuilder();
			for (byte b : hash) {
				hex.append(String.format(Locale.US, "%02X", b));
			}
			return hex.toString();
		} catch (Exception e) {
			return "";
		}
	}

	private static String ratingConstant(String value) {
		switch (value) {
			case "G": return RequestConfiguration.MAX_AD_CONTENT_RATING_G;
			case "T": return RequestConfiguration.MAX_AD_CONTENT_RATING_T;
			case "MA": return RequestConfiguration.MAX_AD_CONTENT_RATING_MA;
			default: return RequestConfiguration.MAX_AD_CONTENT_RATING_PG;
		}
	}

}
