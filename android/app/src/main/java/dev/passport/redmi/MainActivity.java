package dev.passport.redmi;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.animation.ObjectAnimator;
import android.animation.ValueAnimator;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.media.MediaRecorder;
import android.os.*;
import android.util.Log;
import android.util.Base64;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.cert.*;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.*;
import okhttp3.*;

public class MainActivity extends Activity {
    private static final UUID SERVICE = UUID.fromString("b0c6a200-83c8-477a-a051-d567ebc13d01");
    private static final UUID AUTH = UUID.fromString("b0c6a201-83c8-477a-a051-d567ebc13d01");
    private static final UUID CONFIG = UUID.fromString("b0c6a202-83c8-477a-a051-d567ebc13d01");
    private static final UUID PIN = UUID.fromString("b0c6a203-83c8-477a-a051-d567ebc13d01");
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ArrayList<JSONObject> tasks = new ArrayList<>();
    private BluetoothLeScanner scanner;
    private BluetoothGatt gatt;
    private WebSocket socket;
    private OkHttpClient client;
    private EditText codeInput;
    private TextView clock, dateLabel, connection, taskCount, micLabel;
    private LinearLayout taskList;
    private View pairingPanel;
    private ImageButton micButton;
    private FrameLayout drawer, shade;
    private View moduleMenuView, codexScreenView, profileScreenView, fullBioOverlay;
    private ScrollView moduleMenuScroll, codexScroll, profileScroll, fullBioScroll;
    private LinearLayout moduleList, profileCard, fullBioContent;
    private FrameLayout wallpaperView;
    private ImageView companionView;
    private TextView brandView, signatureView;
    private ObjectAnimator floatAnimation;
    private ValueAnimator panelTransition;
    private boolean drawerOpen = false, landscapeMode = false;
    private float panelProgress = 0;
    private int landscapeDrawerWidth, portraitDrawerHeight;
    private float touchStartX, touchStartY;
    private String pairingCode = "", endpoint = "", token = "", fingerprint = "";
    private long lastSnapshot = 0;
    private MediaRecorder recorder;
    private File audioFile;
    private boolean recording = false;
    private int reconnectCount = 0, connectionEpoch = 0;
    private String theme = "ocean";
    private String character = "default";
    private String appearanceSettings = "";
    private long characterRevision = 0;
    private long downloadingCharacter = -1;
    private Bitmap customCharacter;
    private String activeModule = "menu", moduleSettings = "";
    private final ArrayList<String> enabledModules = new ArrayList<>(Arrays.asList("codex", "profile"));
    private JSONArray moduleCatalog = new JSONArray();
    private JSONObject profile = new JSONObject();
    private boolean bioFullscreen = false;
    private int backgroundStart = 0xFF061B3A, backgroundEnd = 0xFF0B4D80;
    private int cream = 0xFFEAF7FF, ink = 0xFF08233F, muted = 0xFF527895;
    private int apple = 0xFF1677FF, line = 0xFFA9DDF5;
    private static final class FeedLine {
        final String title, status, phase, text;
        final long at;
        FeedLine(String title, String status, String phase, String text, long at) {
            this.title = title; this.status = status; this.phase = phase; this.text = text; this.at = at;
        }
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        hideSystemBars();
        buildUI();
        android.content.SharedPreferences saved = getSharedPreferences("passport", MODE_PRIVATE);
        File cachedCharacter = new File(getFilesDir(), "custom-character.png");
        if (cachedCharacter.exists()) customCharacter = BitmapFactory.decodeFile(cachedCharacter.getAbsolutePath());
        characterRevision = saved.getLong("characterRevision", 0);
        String cachedAppearance = saved.getString("appearance", "");
        if (!cachedAppearance.isEmpty()) try { applyAppearance(new JSONObject(cachedAppearance)); } catch (JSONException ignored) {}
        String cached = saved.getString("modules", "");
        if (!cached.isEmpty()) try { applyModules(new JSONObject(cached)); } catch (JSONException ignored) {}
        endpoint = saved.getString("endpoint", "");
        fingerprint = saved.getString("fingerprint", "");
        if (!endpoint.isEmpty() && fingerprint.matches("[a-f0-9]{64}")) connectSocket();
        requestPermissionsIfNeeded();
        ui.post(tick);
    }
    @Override public void onConfigurationChanged(android.content.res.Configuration config) {
        super.onConfigurationChanged(config);
        buildUI();
        codeInput.setText(pairingCode);
        updateConnectionUI();
    }
    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
    }
    @Override public boolean dispatchTouchEvent(MotionEvent event) {
        if (event.getAction() == MotionEvent.ACTION_DOWN) {
            touchStartX = event.getRawX(); touchStartY = event.getRawY();
        }
        boolean handled = super.dispatchTouchEvent(event);
        if (event.getAction() == MotionEvent.ACTION_UP && bioFullscreen) {
            float dx = event.getRawX() - touchStartX, dy = event.getRawY() - touchStartY;
            if ((landscapeMode && dx > dp(65) && Math.abs(dx) > Math.abs(dy)) ||
                (!landscapeMode && dy > dp(65) && Math.abs(dy) > Math.abs(dx) &&
                    (fullBioScroll == null || fullBioScroll.getScrollY() == 0))) {
                showBioFullscreen(false); setDrawer(false);
            }
            return handled;
        }
        if (event.getAction() == MotionEvent.ACTION_UP && drawerOpen && drawer != null) {
            int[] position = new int[2]; drawer.getLocationOnScreen(position);
            boolean fromHeader = touchStartY >= position[1] && touchStartY < position[1] + dp(90);
            float dx = event.getRawX() - touchStartX, dy = event.getRawY() - touchStartY;
            ScrollView visible = activeModule.equals("codex") ? codexScroll : activeModule.equals("profile") ? profileScroll : moduleMenuScroll;
            boolean fromDrawer = touchStartX >= position[0] && touchStartX < position[0] + drawer.getWidth() &&
                touchStartY >= position[1] && touchStartY < position[1] + drawer.getHeight();
            if (fromDrawer && ((landscapeMode && dx > dp(65) && Math.abs(dx) > Math.abs(dy)) ||
                (!landscapeMode && dy > dp(65) && Math.abs(dy) > Math.abs(dx) &&
                    (fromHeader || visible == null || visible.getScrollY() == 0)))) {
                showBioFullscreen(false); setDrawer(false);
            }
        }
        return handled;
    }
    @Override public void onBackPressed() {
        if (bioFullscreen) showBioFullscreen(false);
        else if (drawerOpen) setDrawer(false);
        else super.onBackPressed();
    }
    private void hideSystemBars() {
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams params = getWindow().getAttributes();
            params.layoutInDisplayCutoutMode = Build.VERSION.SDK_INT >= 30
                ? WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                : WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            getWindow().setAttributes(params);
        }
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN |
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_FULLSCREEN |
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    }

    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + .5f); }
    private LinearLayout column() { LinearLayout v = new LinearLayout(this); v.setOrientation(1); return v; }
    private LinearLayout row() { LinearLayout v = new LinearLayout(this); v.setOrientation(0); v.setGravity(Gravity.CENTER_VERTICAL); return v; }
    private TextView label(String value, int sp, int color, boolean bold) {
        TextView v = new TextView(this); v.setText(value); v.setTextSize(sp); v.setTextColor(color);
        v.setIncludeFontPadding(false);
        if (bold) v.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return v;
    }
    private void pad(View view, int h, int v) { view.setPadding(dp(h), dp(v), dp(h), dp(v)); }
    private android.graphics.drawable.GradientDrawable background(int color, int radius) {
        android.graphics.drawable.GradientDrawable d = new android.graphics.drawable.GradientDrawable();
        d.setColor(color); d.setCornerRadius(dp(radius)); return d;
    }
    private android.graphics.drawable.GradientDrawable card(int color, int radius) {
        android.graphics.drawable.GradientDrawable d = background(color, radius);
        d.setStroke(dp(1), line); return d;
    }
    private int blend(int first, int second, float amount) {
        float a = Math.max(0f, Math.min(1f, amount));
        return Color.rgb((int)(Color.red(first) * (1-a) + Color.red(second) * a),
            (int)(Color.green(first) * (1-a) + Color.green(second) * a),
            (int)(Color.blue(first) * (1-a) + Color.blue(second) * a));
    }
    private double luminance(int color) {
        double[] channels = {Color.red(color) / 255.0, Color.green(color) / 255.0, Color.blue(color) / 255.0};
        for (int i = 0; i < channels.length; i++)
            channels[i] = channels[i] <= .04045 ? channels[i] / 12.92 : Math.pow((channels[i] + .055) / 1.055, 2.4);
        return .2126 * channels[0] + .7152 * channels[1] + .0722 * channels[2];
    }
    private double contrast(int foreground, int background) {
        double a = luminance(foreground), b = luminance(background);
        return (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
    }
    private double wallpaperContrast(int foreground) {
        return Math.min(contrast(foreground, backgroundStart), contrast(foreground, backgroundEnd));
    }
    private int wallpaperText(int... candidates) {
        int best = candidates[0]; double score = -1;
        for (int candidate : candidates) {
            double next = wallpaperContrast(candidate);
            if (next > score) { best = candidate; score = next; }
        }
        return best;
    }
    private Button button(String text, int color) {
        Button b = new Button(this); b.setText(text); b.setTextColor(Color.WHITE); b.setAllCaps(false); b.setTextSize(14);
        b.setBackground(background(theme.equals("midnight") ? 0xFF9B4B5B : color, 14)); return b;
    }
    private int color(JSONObject colors, String key, int fallback) {
        try { return Color.parseColor(colors.optString(key)); } catch (Exception ignored) { return fallback; }
    }

    private void applyAppearance(JSONObject settings) {
        if (settings == null) return;
        String serialized = settings.toString();
        long revision = settings.optLong("revision", 0);
        if (serialized.equals(appearanceSettings)) {
            if (character.equals("custom") && revision != characterRevision) downloadCharacter(revision);
            return;
        }
        JSONObject colors = settings.optJSONObject("colors");
        if (colors == null) return;
        theme = settings.optString("theme", "ocean");
        character = settings.optString("character", "default");
        backgroundStart = color(colors, "backgroundStart", 0xFF061B3A);
        backgroundEnd = color(colors, "backgroundEnd", 0xFF0B4D80);
        cream = color(colors, "surface", 0xFFEAF7FF);
        ink = color(colors, "ink", 0xFF08233F);
        muted = color(colors, "muted", 0xFF527895);
        apple = color(colors, "accent", 0xFF1677FF);
        line = color(colors, "line", 0xFFA9DDF5);
        getSharedPreferences("passport", MODE_PRIVATE).edit().putString("appearance", serialized).apply();
        appearanceSettings = serialized;
        if (character.equals("custom") && revision != characterRevision) downloadCharacter(revision);
        buildUI();
        codeInput.setText(pairingCode);
    }

    private void downloadCharacter(long revision) {
        if (client == null || endpoint.isEmpty() || downloadingCharacter == revision) return;
        String[] pieces = endpoint.split(":", 3);
        if (pieces.length != 3) return;
        Request request = new Request.Builder().url("https://" + pieces[0] + ":" + pieces[1] + "/character?token=" + token).build();
        downloadingCharacter = revision;
        client.newCall(request).enqueue(new Callback() {
            @Override public void onFailure(Call call, IOException error) { downloadingCharacter = -1; Log.w("Passport", "Character download failed", error); }
            @Override public void onResponse(Call call, Response response) throws IOException {
                try (ResponseBody body = response.body()) {
                    if (!response.isSuccessful() || body == null) { downloadingCharacter = -1; return; }
                    byte[] bytes = body.bytes();
                    Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
                    if (bitmap == null) { downloadingCharacter = -1; return; }
                    File file = new File(getFilesDir(), "custom-character.png");
                    try (FileOutputStream output = new FileOutputStream(file)) { output.write(bytes); }
                    customCharacter = bitmap; characterRevision = revision; downloadingCharacter = -1;
                    getSharedPreferences("passport", MODE_PRIVATE).edit().putLong("characterRevision", revision).apply();
                    ui.post(() -> { buildUI(); codeInput.setText(pairingCode); });
                }
            }
        });
    }
    private void buildUI() {
        if (floatAnimation != null) floatAnimation.cancel();
        if (panelTransition != null) panelTransition.cancel();
        panelProgress = 0;
        landscapeMode = getResources().getConfiguration().orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE;
        FrameLayout shell = new FrameLayout(this);
        shell.addView(new AmbientView(), new FrameLayout.LayoutParams(-1, -1));
        FrameLayout wallpaper = new FrameLayout(this); wallpaperView = wallpaper;
        shell.addView(wallpaper, new FrameLayout.LayoutParams(-1, -1));
        ImageView companion = new ImageView(this); companionView = companion;
        if (character.equals("custom") && customCharacter != null) companion.setImageBitmap(customCharacter);
        else companion.setImageResource(R.drawable.companion);
        companion.setScaleType(ImageView.ScaleType.FIT_CENTER); companion.setContentDescription("AI 工作伙伴角色");
        FrameLayout.LayoutParams art = new FrameLayout.LayoutParams(dp(landscapeMode ? 500 : 440), dp(landscapeMode ? 500 : 440),
            (landscapeMode ? Gravity.RIGHT : Gravity.CENTER_HORIZONTAL) | Gravity.BOTTOM);
        art.bottomMargin = dp(landscapeMode ? -74 : -25); wallpaper.addView(companion, art);
        floatAnimation = ObjectAnimator.ofFloat(companion, "translationY", dp(3), dp(-5));
        floatAnimation.setDuration(7000); floatAnimation.setRepeatCount(ValueAnimator.INFINITE);
        floatAnimation.setRepeatMode(ValueAnimator.REVERSE); floatAnimation.start();

        int wallpaperPrimary = wallpaperText(ink, cream, Color.WHITE, Color.BLACK);
        int wallpaperSecondary = wallpaperContrast(muted) >= 4.5 ? muted : wallpaperPrimary;
        int wallpaperAccent = wallpaperContrast(apple) >= 4.5 ? apple : wallpaperPrimary;
        TextView brand = label("AI PASSPORT   ✦   WORK COMPANION", 11, wallpaperAccent, true); brandView = brand;
        brand.setLetterSpacing(0.16f);
        FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.LEFT);
        bp.leftMargin = dp(landscapeMode ? 34 : 25); bp.topMargin = dp(landscapeMode ? 30 : 43); wallpaper.addView(brand, bp);
        Date now = new Date();
        clock = label(new SimpleDateFormat("HH:mm", Locale.getDefault()).format(now), landscapeMode ? 72 : 66, wallpaperPrimary, true);
        clock.setTypeface(Typeface.create("serif", Typeface.BOLD));
        FrameLayout.LayoutParams timeP = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.LEFT);
        timeP.leftMargin = dp(landscapeMode ? 30 : 22); timeP.topMargin = dp(landscapeMode ? 57 : 79); wallpaper.addView(clock, timeP);
        dateLabel = label(new SimpleDateFormat("M 月 d 日  ·  EEEE", Locale.SIMPLIFIED_CHINESE).format(now), 14, wallpaperSecondary, false);
        FrameLayout.LayoutParams dateP = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.LEFT);
        dateP.leftMargin = dp(landscapeMode ? 35 : 27); dateP.topMargin = dp(landscapeMode ? 156 : 174); wallpaper.addView(dateLabel, dateP);
        connection = label("● 等待配对", 12, apple, true); pad(connection, 12, 8);
        connection.setBackground(background(cream, 100));
        FrameLayout.LayoutParams statusP = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.LEFT);
        statusP.leftMargin = dp(landscapeMode ? 34 : 25); statusP.topMargin = dp(landscapeMode ? 199 : 217); wallpaper.addView(connection, statusP);
        String skinName = theme.equals("midnight") ? "MIDNIGHT" : theme.equals("custom") ? "MY COMPANION" : "OCEAN LINK";
        TextView signature = label(skinName + "  ·  AI AT WORK", 11, wallpaperSecondary, true); signatureView = signature;
        signature.setLetterSpacing(.18f);
        FrameLayout.LayoutParams sigP = new FrameLayout.LayoutParams(-2, -2,
            Gravity.LEFT | (landscapeMode ? Gravity.BOTTOM : Gravity.TOP));
        sigP.leftMargin = dp(landscapeMode ? 35 : 25);
        if (landscapeMode) sigP.bottomMargin = dp(34); else sigP.topMargin = dp(285);
        wallpaper.addView(signature, sigP);
        View gesture = new View(this);
        final float[] start = new float[2];
        gesture.setOnTouchListener((v, event) -> {
            if (event.getAction() == MotionEvent.ACTION_DOWN) {
                start[0] = event.getX(); start[1] = event.getY();
                if (panelTransition != null) panelTransition.cancel();
                return true;
            }
            if (event.getAction() == MotionEvent.ACTION_MOVE) {
                float dx = event.getX() - start[0], dy = event.getY() - start[1];
                if (landscapeMode && dx < -dp(8) && Math.abs(dx) > Math.abs(dy))
                    setPanelProgress(Math.min(1f, -dx / (wallpaperView.getWidth() * .47f)));
                else if (!landscapeMode && dy < -dp(8) && Math.abs(dy) > Math.abs(dx))
                    setPanelProgress(Math.min(1f, -dy / (wallpaperView.getHeight() * .47f)));
                return true;
            }
            if (event.getAction() == MotionEvent.ACTION_UP) {
                float dx = event.getX() - start[0], dy = event.getY() - start[1];
                if (landscapeMode) setDrawer(panelProgress > .25f ||
                    (dx < -dp(65) && Math.abs(dx) > Math.abs(dy)) ||
                    (Math.abs(dx) < dp(12) && Math.abs(dy) < dp(12)));
                else setDrawer(panelProgress > .25f ||
                    (dy < -dp(65) && Math.abs(dy) > Math.abs(dx)) ||
                    (Math.abs(dx) < dp(12) && Math.abs(dy) < dp(12)));
                return true;
            }
            if (event.getAction() == MotionEvent.ACTION_CANCEL) setDrawer(false);
            return true;
        });
        wallpaper.addView(gesture, new FrameLayout.LayoutParams(-1, -1));

        shade = new FrameLayout(this); shade.setBackgroundColor(Color.TRANSPARENT);
        shade.setVisibility(View.GONE);
        shade.setOnClickListener(v -> setDrawer(false));
        shell.addView(shade, new FrameLayout.LayoutParams(-1, -1));
        drawer = new FrameLayout(this);
        android.graphics.drawable.GradientDrawable drawerBackground = new android.graphics.drawable.GradientDrawable(
            android.graphics.drawable.GradientDrawable.Orientation.TL_BR, new int[]{cream, blend(cream, backgroundEnd, .10f)});
        drawerBackground.setCornerRadius(dp(28)); drawerBackground.setStroke(dp(1), line);
        drawer.setBackground(drawerBackground); drawer.setElevation(dp(18));
        int width = getResources().getDisplayMetrics().widthPixels;
        int height = getResources().getDisplayMetrics().heightPixels;
        landscapeDrawerWidth = (int)(width * (2f / 3f));
        portraitDrawerHeight = (int)(height * (2f / 3f)) - dp(8);
        FrameLayout.LayoutParams drawerP = new FrameLayout.LayoutParams(
            landscapeMode ? landscapeDrawerWidth : width - dp(18),
            landscapeMode ? height - dp(16) : portraitDrawerHeight,
            (landscapeMode ? Gravity.RIGHT : Gravity.CENTER_HORIZONTAL) | Gravity.BOTTOM);
        drawerP.rightMargin = landscapeMode ? dp(8) : 0;
        drawerP.bottomMargin = dp(8);
        shell.addView(drawer, drawerP);
        drawer.setVisibility(drawerOpen ? View.VISIBLE : View.GONE);
        ScrollView menuScroll = new ScrollView(this); moduleMenuScroll = menuScroll; moduleMenuView = menuScroll;
        menuScroll.setVerticalScrollBarEnabled(false);
        drawer.addView(menuScroll, new FrameLayout.LayoutParams(-1, -1));
        LinearLayout menuContent = column(); menuContent.setPadding(dp(20), dp(18), dp(20), dp(24)); menuScroll.addView(menuContent);
        LinearLayout menuHeader = row(); menuContent.addView(menuHeader);
        TextView menuTitle = label("随身功能  /  MODULES", 22, ink, true);
        menuTitle.setTypeface(Typeface.create("serif", Typeface.BOLD));
        menuHeader.addView(menuTitle, new LinearLayout.LayoutParams(0, -2, 1));
        TextView menuClose = label(landscapeMode ? "→ 收起" : "↓ 收起", 13, apple, true);
        pad(menuClose, 10, 8); menuClose.setOnClickListener(v -> setDrawer(false)); menuHeader.addView(menuClose);
        TextView menuHint = label("选择要查看的内容", 13, muted, false);
        LinearLayout.LayoutParams hintP = new LinearLayout.LayoutParams(-1, -2); hintP.topMargin = dp(8); menuContent.addView(menuHint, hintP);
        moduleList = column(); LinearLayout.LayoutParams modulesP = new LinearLayout.LayoutParams(-1, -2);
        modulesP.topMargin = dp(14); menuContent.addView(moduleList, modulesP);
        renderModuleMenu();

        ScrollView feedScroll = new ScrollView(this); codexScroll = feedScroll; codexScreenView = feedScroll;
        feedScroll.setVerticalScrollBarEnabled(false);
        drawer.addView(feedScroll, new FrameLayout.LayoutParams(-1, -1));
        LinearLayout content = column(); content.setPadding(dp(20), dp(18), dp(20), dp(100)); feedScroll.addView(content);
        LinearLayout header = row(); content.addView(header);
        TextView back = label("‹ 功能", 13, apple, true); pad(back, 10, 8);
        back.setOnClickListener(v -> showModule("menu")); header.addView(back);
        TextView title = label("Codex 监看", 22, ink, true); title.setTypeface(Typeface.create("serif", Typeface.BOLD));
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        TextView close = label(landscapeMode ? "→ 收起" : "↓ 收起", 13, apple, true);
        pad(close, 10, 8); close.setOnClickListener(v -> setDrawer(false)); header.addView(close);

        LinearLayout pairing = column(); pad(pairing, 16, 14); pairing.setBackground(card(cream, 20));
        LinearLayout.LayoutParams pairP = new LinearLayout.LayoutParams(-1, -2); pairP.topMargin = dp(16); content.addView(pairing, pairP);
        pairingPanel = pairing;
        pairing.addView(label("连接到这台 Mac", 16, ink, true));
        pairing.addView(label("输入 Mac 管理窗口显示的 6 位配对码", 12, muted, false));
        LinearLayout pairRow = row(); LinearLayout.LayoutParams pr = new LinearLayout.LayoutParams(-1, -2); pr.topMargin = dp(7); pairing.addView(pairRow, pr);
        codeInput = new EditText(this); codeInput.setSingleLine(true); codeInput.setHint("000000"); codeInput.setTextColor(ink); codeInput.setHintTextColor(muted);
        codeInput.setInputType(android.text.InputType.TYPE_CLASS_NUMBER); codeInput.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(6)});
        pairRow.addView(codeInput, new LinearLayout.LayoutParams(0, dp(48), 1));
        Button pair = button("连接 / 配对", apple); pair.setOnClickListener(v -> startPairing()); pairRow.addView(pair);

        LinearLayout titleRow = row(); LinearLayout.LayoutParams titleP = new LinearLayout.LayoutParams(-1, -2);
        titleP.topMargin = dp(17); content.addView(titleRow, titleP);
        TextView feedTitle = label("实时进度", 17, ink, true);
        titleRow.addView(feedTitle, new LinearLayout.LayoutParams(0, -2, 1));
        taskCount = label("0 个任务", 12, muted, false); titleRow.addView(taskCount);
        taskList = column(); LinearLayout.LayoutParams listP = new LinearLayout.LayoutParams(-1, -2); listP.topMargin = dp(6); content.addView(taskList, listP);
        renderTasks();
        micLabel = label(recording ? "录音中 · 再点结束" : "点按录音", 12, ink, true); pad(micLabel, 10, 8);
        micLabel.setBackground(card(cream, 14));
        micButton = new ImageButton(this); micButton.setImageResource(android.R.drawable.ic_btn_speak_now);
        micButton.setColorFilter(Color.WHITE); micButton.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        micButton.setPadding(dp(18), dp(18), dp(18), dp(18));
        micButton.setBackground(background(recording ? ink : (theme.equals("midnight") ? 0xFF9B4B5B : apple), 100));
        micButton.setContentDescription(recording ? "结束录音" : "开始录音");
        FrameLayout.LayoutParams micHintP = new FrameLayout.LayoutParams(-2, -2, Gravity.RIGHT | Gravity.BOTTOM);
        micHintP.rightMargin = dp(85); micHintP.bottomMargin = dp(30); drawer.addView(micLabel, micHintP);
        FrameLayout.LayoutParams micP = new FrameLayout.LayoutParams(dp(58), dp(58), Gravity.RIGHT | Gravity.BOTTOM);
        micP.rightMargin = dp(17); micP.bottomMargin = dp(17); drawer.addView(micButton, micP);
        micButton.setOnClickListener(v -> { if (recording) endRecording(true); else beginRecording(); });

        ScrollView personalScroll = new ScrollView(this); profileScroll = personalScroll; profileScreenView = personalScroll;
        personalScroll.setVerticalScrollBarEnabled(false);
        drawer.addView(personalScroll, new FrameLayout.LayoutParams(-1, -1));
        LinearLayout personalContent = column(); personalContent.setPadding(dp(20), dp(18), dp(20), dp(28));
        personalScroll.addView(personalContent);
        LinearLayout personalHeader = row(); personalContent.addView(personalHeader);
        TextView personalBack = label("‹ 功能", 13, apple, true); pad(personalBack, 10, 8);
        personalBack.setOnClickListener(v -> showModule("menu")); personalHeader.addView(personalBack);
        TextView personalTitle = label("个人名片", 22, ink, true);
        personalTitle.setTypeface(Typeface.create("serif", Typeface.BOLD));
        personalHeader.addView(personalTitle, new LinearLayout.LayoutParams(0, -2, 1));
        TextView personalClose = label(landscapeMode ? "→ 收起" : "↓ 收起", 13, apple, true);
        pad(personalClose, 10, 8); personalClose.setOnClickListener(v -> setDrawer(false)); personalHeader.addView(personalClose);
        profileCard = column(); LinearLayout.LayoutParams personalP = new LinearLayout.LayoutParams(-1, -2);
        personalP.topMargin = dp(16); personalContent.addView(profileCard, personalP);

        FrameLayout bioPage = new FrameLayout(this); fullBioOverlay = bioPage;
        bioPage.setElevation(dp(30));
        bioPage.setBackground(new android.graphics.drawable.GradientDrawable(
            android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
            new int[]{blend(cream, Color.WHITE, .15f), blend(cream, backgroundEnd, .16f)}));
        shell.addView(bioPage, new FrameLayout.LayoutParams(-1, -1));
        ScrollView bioScroll = new ScrollView(this); fullBioScroll = bioScroll; bioScroll.setVerticalScrollBarEnabled(false);
        bioPage.addView(bioScroll, new FrameLayout.LayoutParams(-1, -1));
        fullBioContent = column(); fullBioContent.setPadding(dp(landscapeMode ? 60 : 30), dp(75),
            dp(landscapeMode ? 60 : 30), dp(36)); bioScroll.addView(fullBioContent);
        TextView bioClose = label("×  关闭", 15, apple, true); pad(bioClose, 12, 8);
        FrameLayout.LayoutParams bioCloseP = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.RIGHT);
        bioCloseP.topMargin = dp(19); bioCloseP.rightMargin = dp(22); bioPage.addView(bioClose, bioCloseP);
        bioClose.setOnClickListener(v -> showBioFullscreen(false));
        renderProfile();
        showModule(activeModule);
        showBioFullscreen(bioFullscreen);
        setContentView(shell);
        if (drawerOpen) drawer.post(() -> setPanelProgress(1f));
        updateConnectionUI();
    }

    private void setDrawer(boolean open) {
        drawerOpen = open;
        animatePanel(open ? 1f : 0f);
    }

    private void animatePanel(float target) {
        if (panelTransition != null) panelTransition.cancel();
        if (Math.abs(target - panelProgress) < .001f) {
            setPanelProgress(target);
            if (target == 0) {
                drawer.setVisibility(View.GONE); shade.setVisibility(View.GONE);
                if (floatAnimation != null && !floatAnimation.isRunning()) floatAnimation.start();
            }
            return;
        }
        panelTransition = ValueAnimator.ofFloat(panelProgress, target);
        panelTransition.setDuration((long)(380 * Math.abs(target - panelProgress)) + 120);
        panelTransition.setInterpolator(new android.view.animation.DecelerateInterpolator());
        panelTransition.addUpdateListener(animation -> setPanelProgress((float)animation.getAnimatedValue()));
        panelTransition.addListener(new android.animation.AnimatorListenerAdapter() {
            private boolean cancelled;
            @Override public void onAnimationCancel(android.animation.Animator animation) { cancelled = true; }
            @Override public void onAnimationEnd(android.animation.Animator animation) {
                if (!cancelled && target == 0) {
                    drawer.setVisibility(View.GONE); shade.setVisibility(View.GONE);
                    if (floatAnimation != null) floatAnimation.start();
                }
            }
        });
        panelTransition.start();
    }

    private void setPanelProgress(float progress) {
        if (drawer == null || wallpaperView.getWidth() == 0) return;
        panelProgress = Math.max(0f, Math.min(1f, progress));
        float p = panelProgress;
        if (p > 0 && floatAnimation != null && floatAnimation.isRunning()) floatAnimation.cancel();
        drawer.setVisibility(View.VISIBLE);
        shade.setVisibility(p > 0 ? View.VISIBLE : View.GONE);
        drawer.setTranslationX(landscapeMode ? (landscapeDrawerWidth + dp(8)) * (1f - p) : 0);
        drawer.setTranslationY(landscapeMode ? 0 : (portraitDrawerHeight + dp(8)) * (1f - p));
        float startX = companionView.getLeft() + companionView.getWidth() / 2f;
        float startY = companionView.getTop() + companionView.getHeight() / 2f;
        float endX = landscapeMode ? wallpaperView.getWidth() / 6f : wallpaperView.getWidth() * .74f;
        float endY = landscapeMode
            ? wallpaperView.getHeight() - companionView.getHeight() * .48f / 2f + dp(18)
            : wallpaperView.getHeight() / 6f;
        float scale = landscapeMode ? 1f - .52f * p : 1f - .58f * p;
        companionView.setScaleX(scale); companionView.setScaleY(scale);
        companionView.setTranslationX((endX - startX) * p);
        companionView.setTranslationY((endY - startY) * p);
        clock.setPivotX(0); clock.setPivotY(0);
        clock.setScaleX(1f - (landscapeMode ? .42f : .34f) * p);
        clock.setScaleY(1f - (landscapeMode ? .42f : .34f) * p);
        clock.setTranslationY(landscapeMode ? 0 : -dp(42) * p);
        dateLabel.setTranslationY(-dp(landscapeMode ? 40 : 70) * p);
        connection.setTranslationY(-dp(landscapeMode ? 60 : 70) * p);
        brandView.setPivotX(0); brandView.setPivotY(0);
        brandView.setScaleX(1f - .17f * p); brandView.setScaleY(1f - .17f * p);
        brandView.setAlpha(landscapeMode ? 1f : 1f - p);
        signatureView.setAlpha(1f - p);
    }

    private void renderModuleMenu() {
        if (moduleList == null) return;
        moduleList.removeAllViews();
        if (enabledModules.isEmpty()) {
            TextView empty = label("暂时没有启用功能。请在电脑端的「模块中心」中选择。", 14, muted, false);
            pad(empty, 18, 20); empty.setBackground(card(cream, 18)); moduleList.addView(empty);
            return;
        }
        for (String id : enabledModules) {
            boolean codexModule = id.equals("codex");
            JSONObject definition = moduleDefinition(id);
            String name = definition == null ? (codexModule ? "Codex 监看" : "个人名片")
                : definition.optString("shortName", definition.optString("name"));
            String summary = definition == null ? (codexModule ? "实时进度与语音命令" : "简介、网站与联系方式")
                : definition.optString("summary");
            String iconValue = definition == null ? (codexModule ? "◉" : "✦") : definition.optString("phoneIcon", "✦");
            LinearLayout tile = row(); pad(tile, 17, 18); tile.setMinimumHeight(dp(92));
            tile.setBackground(card(cream, 20)); tile.setOnClickListener(v -> showModule(id));
            LinearLayout.LayoutParams tileP = new LinearLayout.LayoutParams(-1, -2);
            tileP.bottomMargin = dp(11); moduleList.addView(tile, tileP);
            TextView icon = label(iconValue, 24, apple, true);
            icon.setGravity(Gravity.CENTER); icon.setBackground(background(
                theme.equals("midnight") ? 0xFF483543 : 0xFFF7E7DA, 14));
            tile.addView(icon, new LinearLayout.LayoutParams(dp(54), dp(54)));
            LinearLayout text = column(); LinearLayout.LayoutParams textP = new LinearLayout.LayoutParams(0, -2, 1);
            textP.leftMargin = dp(15); tile.addView(text, textP);
            text.addView(label(name, 17, ink, true));
            TextView detail = label(summary, 12, muted, false); detail.setMaxLines(2);
            LinearLayout.LayoutParams detailP = new LinearLayout.LayoutParams(-1, -2);
            detailP.topMargin = dp(5); text.addView(detail, detailP);
            tile.addView(label("›", 25, apple, false));
        }
    }

    private JSONObject moduleDefinition(String id) {
        for (int i = 0; i < moduleCatalog.length(); i++) {
            JSONObject value = moduleCatalog.optJSONObject(i);
            if (value != null && id.equals(value.optString("id"))) return value;
        }
        return null;
    }

    private void applyModuleCatalog(JSONArray catalog) {
        if (catalog == null) return;
        moduleCatalog = catalog;
        renderModuleMenu();
    }

    private void showModule(String id) {
        if (!id.equals("menu") && !enabledModules.contains(id)) id = "menu";
        if (recording && !id.equals("codex")) endRecording(false);
        activeModule = id;
        if (moduleMenuView == null) return;
        moduleMenuView.setVisibility(id.equals("menu") ? View.VISIBLE : View.GONE);
        codexScreenView.setVisibility(id.equals("codex") ? View.VISIBLE : View.GONE);
        profileScreenView.setVisibility(id.equals("profile") ? View.VISIBLE : View.GONE);
        micButton.setVisibility(id.equals("codex") ? View.VISIBLE : View.GONE);
        if (!id.equals("codex")) micLabel.setVisibility(View.GONE);
        else setMicText(micLabel.getText().toString());
    }

    private void renderProfile() {
        if (profileCard == null || fullBioContent == null) return;
        profileCard.removeAllViews(); fullBioContent.removeAllViews();
        profileCard.setBackground(card(cream, 22)); pad(profileCard, 23, 23);
        String name = profile.optString("name").trim();
        String headline = profile.optString("headline").trim();
        String bio = profile.optString("bio").trim();
        profileCard.addView(label("✦  PERSONAL CARD", 11, apple, true));
        TextView displayName = label(name.isEmpty() ? "你的名字" : name, 28, ink, true);
        displayName.setTypeface(Typeface.create("serif", Typeface.BOLD));
        LinearLayout.LayoutParams nameP = new LinearLayout.LayoutParams(-1, -2);
        nameP.topMargin = dp(18); profileCard.addView(displayName, nameP);
        if (!headline.isEmpty()) {
            TextView line = label(headline, 14, muted, false);
            LinearLayout.LayoutParams lineP = new LinearLayout.LayoutParams(-1, -2);
            lineP.topMargin = dp(6); profileCard.addView(line, lineP);
        }
        View divider = new View(this); divider.setBackgroundColor(this.line);
        LinearLayout.LayoutParams dividerP = new LinearLayout.LayoutParams(-1, dp(1));
        dividerP.topMargin = dp(20); dividerP.bottomMargin = dp(19); profileCard.addView(divider, dividerP);
        TextView intro = label(bio.isEmpty() ? "在 Mac 的「手机功能」中填写自我介绍。" : bio, 14, ink, false);
        intro.setLineSpacing(dp(5), 1f); intro.setMaxLines(5); intro.setEllipsize(android.text.TextUtils.TruncateAt.END);
        profileCard.addView(intro);
        addProfileLine("网站", profile.optString("website"));
        addProfileLine("邮箱", profile.optString("email"));
        addProfileLine("联系", profile.optString("contact"));
        Button expand = button("全屏查看名片", apple);
        LinearLayout.LayoutParams expandP = new LinearLayout.LayoutParams(-1, dp(48));
        expandP.topMargin = dp(22); profileCard.addView(expand, expandP);
        expand.setOnClickListener(v -> showBioFullscreen(true));

        fullBioContent.addView(label("✦  PERSONAL CARD", 12, apple, true));
        TextView fullName = label(name.isEmpty() ? "个人简介" : name, landscapeMode ? 44 : 38, ink, true);
        fullName.setTypeface(Typeface.create("serif", Typeface.BOLD));
        LinearLayout.LayoutParams fullNameP = new LinearLayout.LayoutParams(-1, -2);
        fullNameP.topMargin = dp(20); fullBioContent.addView(fullName, fullNameP);
        if (!headline.isEmpty()) {
            TextView fullHeadline = label(headline, 17, muted, false);
            LinearLayout.LayoutParams hP = new LinearLayout.LayoutParams(-1, -2);
            hP.topMargin = dp(9); fullBioContent.addView(fullHeadline, hP);
        }
        View fullDivider = new View(this); fullDivider.setBackgroundColor(line);
        LinearLayout.LayoutParams fdP = new LinearLayout.LayoutParams(-1, dp(1));
        fdP.topMargin = dp(27); fdP.bottomMargin = dp(26); fullBioContent.addView(fullDivider, fdP);
        TextView fullText = label(bio.isEmpty() ? "自我介绍还没有填写。可以在 Mac 的 AI Passport 管理应用里编辑。" : bio,
            landscapeMode ? 20 : 18, ink, false);
        fullText.setLineSpacing(dp(9), 1f); fullText.setTextIsSelectable(true); fullBioContent.addView(fullText);
        String website = profile.optString("website").trim();
        String email = profile.optString("email").trim();
        String contact = profile.optString("contact").trim();
        if (!website.isEmpty() || !email.isEmpty() || !contact.isEmpty()) {
            LinearLayout details = column(); pad(details, 22, 20); details.setBackground(card(cream, 22));
            LinearLayout.LayoutParams detailsP = new LinearLayout.LayoutParams(-1, -2);
            detailsP.topMargin = dp(32); fullBioContent.addView(details, detailsP);
            details.addView(label("联系我  /  CONTACT", 13, apple, true));
            addFullProfileLine(details, "个人网站", website);
            addFullProfileLine(details, "邮箱", email);
            addFullProfileLine(details, "其他联系方式", contact);
        }
    }

    private void addFullProfileLine(LinearLayout parent, String title, String value) {
        if (value.isEmpty()) return;
        TextView key = label(title, 12, muted, true);
        LinearLayout.LayoutParams keyP = new LinearLayout.LayoutParams(-1, -2);
        keyP.topMargin = dp(20); parent.addView(key, keyP);
        TextView detail = label(value, 17, ink, false);
        detail.setTextIsSelectable(true); detail.setLineSpacing(dp(4), 1f);
        LinearLayout.LayoutParams detailP = new LinearLayout.LayoutParams(-1, -2);
        detailP.topMargin = dp(7); parent.addView(detail, detailP);
    }

    private void addProfileLine(String title, String value) {
        if (value.trim().isEmpty()) return;
        LinearLayout row = row(); LinearLayout.LayoutParams rowP = new LinearLayout.LayoutParams(-1, -2);
        rowP.topMargin = dp(15); profileCard.addView(row, rowP);
        TextView key = label(title, 12, muted, true); row.addView(key, new LinearLayout.LayoutParams(dp(48), -2));
        TextView detail = label(value, 13, ink, false); detail.setTextIsSelectable(true);
        row.addView(detail, new LinearLayout.LayoutParams(0, -2, 1));
    }

    private void showBioFullscreen(boolean show) {
        bioFullscreen = show;
        if (fullBioOverlay != null) {
            fullBioOverlay.setVisibility(show ? View.VISIBLE : View.GONE);
            if (show) fullBioOverlay.bringToFront();
        }
    }

    private void applyModules(JSONObject settings) {
        if (settings == null) return;
        String serialized = settings.toString();
        if (serialized.equals(moduleSettings)) return;
        JSONArray values = settings.optJSONArray("enabled");
        if (values == null) return;
        enabledModules.clear();
        for (int i = 0; i < values.length(); i++) {
            String id = values.optString(i);
            if ((id.equals("codex") || id.equals("profile")) && !enabledModules.contains(id)) enabledModules.add(id);
        }
        JSONObject next = settings.optJSONObject("profile");
        profile = next == null ? new JSONObject() : next;
        moduleSettings = serialized;
        getSharedPreferences("passport", MODE_PRIVATE).edit().putString("modules", serialized).apply();
        if (!enabledModules.contains("profile") && bioFullscreen) showBioFullscreen(false);
        renderModuleMenu(); renderProfile(); showModule(activeModule);
    }

    private class AmbientView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        AmbientView() {
            super(MainActivity.this);
            setBackground(new android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TL_BR,
                new int[]{backgroundStart, blend(backgroundStart, backgroundEnd, .52f), backgroundEnd}));
        }
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float w = getWidth(), h = getHeight();
            long now = System.currentTimeMillis();
            paint.setStyle(Paint.Style.FILL);
            paint.setColor((apple & 0x00FFFFFF) | 0x22000000); canvas.drawCircle(w * .82f, h * .18f, Math.min(w, h) * .36f, paint);
            paint.setColor((line & 0x00FFFFFF) | 0x28000000); canvas.drawCircle(w * .12f, h * .88f, Math.min(w, h) * .28f, paint);
            for (int i = 0; i < 9; i++) {
                double t = now / 5000.0 + i * 1.7;
                float x = w * ((i * 31 % 89) + 6) / 100f + dp((float)(5 * Math.sin(t)));
                float y = h * ((i * 43 % 77) + 10) / 100f + dp((float)(7 * Math.cos(t * .8)));
                paint.setColor(i % 3 == 0 ? ((apple & 0x00FFFFFF) | 0x88000000)
                    : ((line & 0x00FFFFFF) | 0x77000000));
                canvas.save(); canvas.translate(x, y); canvas.rotate((float)(now / 160.0 + i * 35));
                canvas.drawOval(-dp(2), -dp(7), dp(2), dp(7), paint);
                canvas.drawOval(-dp(7), -dp(2), dp(7), dp(2), paint);
                canvas.restore();
            }
            postInvalidateDelayed(500);
        }
    }

    private void renderTasks() {
        if (taskList == null) return;
        taskList.removeAllViews();
        taskCount.setText(tasks.size() + " 个任务");
        ArrayList<FeedLine> feed = new ArrayList<>();
        for (JSONObject task : tasks) {
            String title = task.optString("title", task.optString("project", "Codex"));
            if (title.length() > 14) title = title.substring(0, 14) + "…";
            String status = task.optString("status");
            JSONArray updates = task.optJSONArray("updates");
            if (updates != null) for (int i = 0; i < updates.length(); i++) {
                JSONObject item = updates.optJSONObject(i);
                if (item != null && !item.optString("text").isEmpty())
                    feed.add(new FeedLine(title, status, item.optString("phase"), item.optString("text"), item.optLong("at")));
            }
            if ((updates == null || updates.length() == 0) && !task.optString("summary").isEmpty())
                feed.add(new FeedLine(title, status, "final", task.optString("summary"), task.optLong("updatedAt")));
            if ((updates == null || updates.length() == 0) && task.optString("summary").isEmpty() && status.equals("working"))
                feed.add(new FeedLine(title, status, "commentary", "正在处理，等待新的进度消息…", task.optLong("updatedAt")));
        }
        feed.sort((a, b) -> Long.compare(b.at, a.at));
        if (feed.isEmpty()) { taskList.addView(label("连接后，这里会出现最新的工作进度。", 13, muted, false)); return; }
        for (int i = 0; i < Math.min(feed.size(), 10); i++) {
            FeedLine line = feed.get(i);
            LinearLayout item = column(); pad(item, 15, 13); item.setBackground(card(cream, 18));
            LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(-1, -2); ip.topMargin = dp(8); taskList.addView(item, ip);
            LinearLayout header = row(); item.addView(header);
            int accent = line.status.equals("working") ? apple : Color.rgb(203, 165, 123);
            header.addView(label("●", 14, accent, true));
            TextView name = label("  " + line.title + "  ·  " + (line.phase.equals("final") ? "结果" : "进度"), 12, muted, true);
            header.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
            String time = new SimpleDateFormat("HH:mm", Locale.getDefault()).format(new Date(line.at));
            header.addView(label(time, 11, muted, false));
            TextView message = label(line.text, 14, ink, false); message.setLineSpacing(dp(3), 1f);
            LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(-1, -2); mp.topMargin = dp(8); item.addView(message, mp);
        }
    }

    private final Runnable tick = new Runnable() {
        @Override public void run() {
            clock.setText(new SimpleDateFormat("HH:mm", Locale.getDefault()).format(new Date()));
            dateLabel.setText(new SimpleDateFormat("M 月 d 日  ·  EEEE", Locale.SIMPLIFIED_CHINESE).format(new Date()));
            updateConnectionUI();
            ui.postDelayed(this, 1000);
        }
    };
    private void updateConnectionUI() {
        if (connection == null || pairingPanel == null) return;
        boolean fresh = lastSnapshot > 0 && System.currentTimeMillis() - lastSnapshot < 7000;
        if (fresh) connection.setText("● 已连接");
        else if (lastSnapshot > 0) connection.setText("● 数据已过期");
        pairingPanel.setVisibility(fresh ? View.GONE : View.VISIBLE);
    }

    private void requestPermissionsIfNeeded() {
        ArrayList<String> missing = new ArrayList<>();
        for (String permission : new String[]{Manifest.permission.RECORD_AUDIO, Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT})
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) missing.add(permission);
        if (!missing.isEmpty()) requestPermissions(missing.toArray(new String[0]), 7);
    }

    private void notice(String message) { ui.post(() -> Toast.makeText(this, message, Toast.LENGTH_LONG).show()); }
    private void state(String value) { ui.post(() -> connection.setText("● " + value)); }

    @SuppressWarnings("MissingPermission") private void startPairing() {
        pairingCode = codeInput.getText().toString().trim();
        if (!pairingCode.matches("[0-9]{6}")) { notice("请输入电脑显示的 6 位配对码"); return; }
        state("通过 USB 查找电脑");
        Request request = new Request.Builder().url("http://127.0.0.1:3221/pair?code=" + pairingCode).build();
        new OkHttpClient.Builder().callTimeout(2, java.util.concurrent.TimeUnit.SECONDS).build().newCall(request).enqueue(new Callback() {
            @Override public void onFailure(Call call, IOException error) { ui.post(() -> startBluetoothPairing()); }
            @Override public void onResponse(Call call, Response response) throws IOException {
                try (ResponseBody body = response.body()) {
                    if (!response.isSuccessful() || body == null) { ui.post(() -> startBluetoothPairing()); return; }
                    try {
                        JSONObject result = new JSONObject(body.string());
                        endpoint = result.getString("endpoint");
                        fingerprint = result.getString("fingerprint");
                        ui.post(() -> { state("USB 配对成功"); client = null; connectSocket(); });
                    } catch (JSONException error) { ui.post(() -> startBluetoothPairing()); }
                }
            }
        });
    }

    @SuppressWarnings("MissingPermission") private void startBluetoothPairing() {
        if (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            requestPermissionsIfNeeded(); return;
        }
        BluetoothManager manager = getSystemService(BluetoothManager.class);
        BluetoothAdapter adapter = manager == null ? null : manager.getAdapter();
        if (adapter == null || !adapter.isEnabled()) { notice("请开启蓝牙"); return; }
        if (scanner != null) scanner.stopScan(scanCallback);
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) { notice("蓝牙扫描不可用"); return; }
        state("查找 Mac");
        ScanFilter filter = new ScanFilter.Builder().setServiceUuid(new ParcelUuid(SERVICE)).build();
        scanner.startScan(Collections.singletonList(filter), new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scanCallback);
        ui.postDelayed(() -> { if (scanner != null) { scanner.stopScan(scanCallback); scanner = null; } }, 15000);
    }
    private final ScanCallback scanCallback = new ScanCallback() {
        @Override @SuppressWarnings("MissingPermission") public void onScanResult(int callbackType, ScanResult result) {
            if (scanner != null) { scanner.stopScan(this); scanner = null; }
            state("蓝牙连接中");
            if (gatt != null) gatt.close();
            gatt = result.getDevice().connectGatt(MainActivity.this, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
        }
        @Override public void onScanFailed(int errorCode) { state("蓝牙扫描失败 " + errorCode); }
    };
    private BluetoothGattCharacteristic character(UUID id) {
        if (gatt == null) return null;
        BluetoothGattService service = gatt.getService(SERVICE);
        return service == null ? null : service.getCharacteristic(id);
    }
    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override @SuppressWarnings("MissingPermission") public void onConnectionStateChange(BluetoothGatt g, int status, int newState) {
            if (newState == BluetoothProfile.STATE_CONNECTED) { state("蓝牙已连接"); g.requestMtu(247); }
            else if (newState == BluetoothProfile.STATE_DISCONNECTED) state("蓝牙已断开");
        }
        @Override @SuppressWarnings("MissingPermission") public void onMtuChanged(BluetoothGatt g, int mtu, int status) { g.discoverServices(); }
        @Override @SuppressWarnings("MissingPermission") public void onServicesDiscovered(BluetoothGatt g, int status) {
            Log.i("Passport", "services discovered status=" + status + " count=" + g.getServices().size() + " service=" + g.getService(SERVICE));
            BluetoothGattCharacteristic c = character(AUTH);
            if (c == null) { state("找不到配对服务"); return; }
            byte[] data = pairingCode.getBytes(StandardCharsets.UTF_8);
            if (Build.VERSION.SDK_INT >= 33) Log.i("Passport", "write result=" + g.writeCharacteristic(c, data, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT));
            else { c.setValue(data); Log.i("Passport", "write result=" + g.writeCharacteristic(c)); }
        }
        @Override @SuppressWarnings("MissingPermission") public void onCharacteristicWrite(BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
            Log.i("Passport", "write callback status=" + status);
            if (status != BluetoothGatt.GATT_SUCCESS) { state("配对码错误或蓝牙未授权"); return; }
            g.readCharacteristic(character(CONFIG));
        }
        @Override @SuppressWarnings("MissingPermission") public void onCharacteristicRead(BluetoothGatt g, BluetoothGattCharacteristic c, byte[] value, int status) {
            Log.i("Passport", "read callback uuid=" + c.getUuid() + " status=" + status + " len=" + (value == null ? 0 : value.length));
            if (status != BluetoothGatt.GATT_SUCCESS) { state("读取配对信息失败"); return; }
            if (c.getUuid().equals(CONFIG)) { endpoint = new String(value, StandardCharsets.UTF_8); g.readCharacteristic(character(PIN)); }
            else if (c.getUuid().equals(PIN)) {
                fingerprint = new String(value, StandardCharsets.UTF_8);
                ui.post(() -> { client = null; connectSocket(); });
            }
        }
        @Override @SuppressWarnings("MissingPermission") public void onCharacteristicRead(BluetoothGatt g, BluetoothGattCharacteristic c, int status) {
            onCharacteristicRead(g, c, c.getValue(), status);
        }
    };

    private void connectSocket() {
        int epoch = ++connectionEpoch;
        String[] pieces = endpoint.split(":", 3);
        if (pieces.length != 3 || !fingerprint.matches("[a-f0-9]{64}")) { state("配对数据无效"); return; }
        token = pieces[2];
        if (client == null) {
            try { client = pinnedClient(fingerprint); }
            catch (Exception e) { state("证书校验配置失败"); return; }
        }
        if (socket != null) socket.cancel();
        state("连接 Wi-Fi");
        Request request = new Request.Builder().url("wss://" + pieces[0] + ":" + pieces[1] + "/?token=" + token).build();
        socket = client.newWebSocket(request, new WebSocketListener() {
            @Override public void onOpen(WebSocket s, Response response) {
                if (epoch != connectionEpoch) { s.cancel(); return; }
                getSharedPreferences("passport", MODE_PRIVATE).edit()
                    .putString("endpoint", endpoint).putString("fingerprint", fingerprint).apply();
                reconnectCount = 0; state("已连接"); s.send("{\"type\":\"refresh\"}");
            }
            @Override public void onMessage(WebSocket s, String value) { ui.post(() -> handleMessage(value)); }
            @Override public void onFailure(WebSocket s, Throwable t, Response response) { Log.e("Passport", "Wi-Fi/TLS connection failed", t); retry(epoch); }
            @Override public void onClosed(WebSocket s, int code, String reason) { Log.w("Passport", "Socket closed: " + code + " " + reason); retry(epoch); }
        });
    }
    private void retry(int epoch) {
        if (epoch != connectionEpoch) return;
        state("数据已过期");
        int attempt = ++reconnectCount;
        ui.postDelayed(() -> { if (epoch == connectionEpoch) connectSocket(); }, Math.min(30000, 3000L * attempt));
    }
    private OkHttpClient pinnedClient(String expected) throws Exception {
        X509TrustManager trust = new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] chain, String authType) throws CertificateException { throw new CertificateException("Client certificate not accepted"); }
            public void checkServerTrusted(X509Certificate[] chain, String authType) throws CertificateException {
                if (chain == null || chain.length == 0) throw new CertificateException("No server certificate");
                try {
                    byte[] hash = MessageDigest.getInstance("SHA-256").digest(chain[0].getEncoded());
                    StringBuilder value = new StringBuilder(); for (byte b : hash) value.append(String.format(Locale.ROOT, "%02x", b & 255));
                    if (!expected.equals(value.toString())) throw new CertificateException("Certificate fingerprint changed");
                } catch (NoSuchAlgorithmException | CertificateEncodingException e) { throw new CertificateException(e); }
            }
        };
        SSLContext tls = SSLContext.getInstance("TLS"); tls.init(null, new TrustManager[]{trust}, new SecureRandom());
        return new OkHttpClient.Builder().sslSocketFactory(tls.getSocketFactory(), trust).hostnameVerifier((host, session) -> true)
            .pingInterval(20, TimeUnit.SECONDS).readTimeout(0, TimeUnit.MILLISECONDS).build();
    }

    private void handleMessage(String raw) {
        try {
            JSONObject event = new JSONObject(raw);
            String type = event.optString("type");
            if (type.equals("snapshot")) {
                applyAppearance(event.optJSONObject("appearance"));
                applyModuleCatalog(event.optJSONArray("moduleCatalog"));
                applyModules(event.optJSONObject("modules"));
                tasks.clear(); JSONArray values = event.optJSONArray("tasks");
                if (values != null) for (int i = 0; i < values.length(); i++) tasks.add(values.getJSONObject(i));
                lastSnapshot = System.currentTimeMillis(); updateConnectionUI(); renderTasks();
            } else if (type.equals("appearance")) applyAppearance(event.optJSONObject("appearance"));
            else if (type.equals("modules")) {
                applyModuleCatalog(event.optJSONArray("moduleCatalog"));
                applyModules(event.optJSONObject("modules"));
            }
            else if (type.equals("transcript")) showTranscript(event.optString("text"));
            else if (type.equals("command_result")) notice("命令已发送到 Codex");
            else if (type.equals("error")) notice(event.optString("message", "未知错误"));
        } catch (JSONException e) { notice("数据格式错误"); }
    }
    private void showTranscript(String text) {
        setMicText("点按录音");
        if (text.isEmpty()) { notice("未识别到语音"); return; }
        AlertDialog.Builder dialog = new AlertDialog.Builder(this).setTitle("确认语音命令").setMessage(text)
            .setNegativeButton("取消", null)
            .setPositiveButton("发送到新任务", (d, w) -> sendCommand(text, null));
        ArrayList<JSONObject> idle = new ArrayList<>();
        for (JSONObject task : tasks) if (!task.optString("status").equals("working")) idle.add(task);
        if (!idle.isEmpty()) dialog.setNeutralButton("选择已有任务", (d, w) -> chooseTarget(text, idle));
        dialog.show();
    }
    private void chooseTarget(String text, ArrayList<JSONObject> idle) {
        String[] names = new String[idle.size()];
        for (int i = 0; i < idle.size(); i++) names[i] = idle.get(i).optString("title", "Codex 任务");
        new AlertDialog.Builder(this).setTitle("发送到哪个任务？")
            .setItems(names, (d, which) -> sendCommand(text, idle.get(which).optString("id")))
            .setNegativeButton("取消", null).show();
    }
    private void sendCommand(String text, String taskId) {
        if (socket == null) { notice("请先连接 Mac"); return; }
        try {
            JSONObject command = new JSONObject().put("type", "command").put("text", text).put("requestId", UUID.randomUUID().toString());
            if (taskId != null) command.put("threadId", taskId);
            socket.send(command.toString());
        } catch (JSONException e) { notice("无法发送命令"); }
    }

    private void beginRecording() {
        if (socket == null || lastSnapshot == 0 || System.currentTimeMillis() - lastSnapshot > 7000) { notice("请先连接 Mac"); return; }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) { requestPermissionsIfNeeded(); return; }
        try {
            audioFile = new File(getCacheDir(), "voice.m4a");
            recorder = Build.VERSION.SDK_INT >= 31 ? new MediaRecorder(this) : new MediaRecorder();
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC);
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
            recorder.setAudioEncodingBitRate(64000); recorder.setAudioSamplingRate(16000);
            recorder.setOutputFile(audioFile.getAbsolutePath()); recorder.prepare(); recorder.start();
            recording = true; setMicText("录音中 · 再点结束");
            micButton.setBackground(background(ink, 100)); micButton.setContentDescription("结束录音");
        } catch (Exception e) {
            recording = false;
            if (recorder != null) { recorder.release(); recorder = null; }
            notice("无法使用麦克风：" + e.getMessage());
        }
    }
    private void endRecording(boolean send) {
        if (!recording) return;
        recording = false;
        try { recorder.stop(); } catch (RuntimeException e) { send = false; }
        recorder.release(); recorder = null;
        micButton.setBackground(background(theme.equals("midnight") ? 0xFF9B4B5B : apple, 100)); micButton.setContentDescription("开始录音");
        setMicText(send ? "Mac 正在本地转写…" : "点按录音");
        if (!send) { audioFile.delete(); return; }
        try {
            byte[] bytes = new byte[(int)audioFile.length()];
            try (FileInputStream stream = new FileInputStream(audioFile)) { if (stream.read(bytes) != bytes.length) throw new IOException("Incomplete audio"); }
            if (bytes.length > 5 * 1024 * 1024) throw new IOException("录音过长");
            JSONObject audio = new JSONObject().put("type", "audio").put("requestId", UUID.randomUUID().toString())
                .put("data", Base64.encodeToString(bytes, Base64.NO_WRAP));
            socket.send(audio.toString()); audioFile.delete();
        } catch (Exception e) { setMicText("点按录音"); notice("发送录音失败：" + e.getMessage()); }
    }
    private void setMicText(String text) {
        if (micLabel == null) return;
        micLabel.setText(text);
        boolean landscape = getResources().getConfiguration().orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE;
        micLabel.setVisibility(activeModule.equals("codex") && (!landscape || !text.equals("点按录音"))
            ? View.VISIBLE : View.GONE);
    }

    @Override @SuppressWarnings("MissingPermission") protected void onDestroy() {
        ui.removeCallbacks(tick);
        if (floatAnimation != null) floatAnimation.cancel();
        if (panelTransition != null) panelTransition.cancel();
        if (recorder != null) { try { recorder.stop(); } catch (Exception ignored) {} recorder.release(); }
        if (scanner != null) scanner.stopScan(scanCallback);
        if (gatt != null) gatt.close();
        if (socket != null) socket.cancel();
        if (client != null) client.dispatcher().executorService().shutdown();
        super.onDestroy();
    }
}
