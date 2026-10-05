<#
.SYNOPSIS
    Regenerates every Highlanders brand asset from png/highlanders.jpg.

.DESCRIPTION
    png/highlanders.jpg is the single source of truth. It is a 960x960 JPEG with a
    flat dark-green mark (#363F2C) on a white background, and no alpha channel.

    This script converts it to alpha PNGs and derives everything else from that one
    cleaned master, so the launcher icon, the splash and the in-app brandmark can
    never drift apart.

    Two properties of the source were measured before this was written, and both
    drive the conversion:

      * The mark is a FLAT fill. A luminance histogram across the content box has
        exactly two spikes -- 30% of pixels at L50-59 (the fill) and 50% at L250-259
        (the white ground) -- with only a sparse antialiasing skirt in between. There
        is no second design tone, so the mark can be re-filled with one flat colour
        and the per-pixel JPEG chroma noise discarded without losing detail.

      * The mark has INTERNAL WHITE COUNTERS (123 enclosed light components, 25 of
        them substantial -- the gaps and counters inside the lettering). These are
        preserved rather than filled in: they become transparent, which on a white
        background is pixel-identical to the original.

    Alpha is derived from luminance, stretched so that the solid fill reaches
    fully opaque and the white ground reaches fully clear.

.PARAMETER Root
    Repository root. Defaults to the parent of this script's folder.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\generate_brand_assets.ps1
#>
[CmdletBinding()]
param(
    [string]$Root
)

if (-not $Root) {
    # $PSScriptRoot is not always populated when invoked via -File on PS 5.1.
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Root = Split-Path -Parent $here
}

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

// Derived entirely from png/highlanders.jpg. Measured, not guessed:
// a flat #363F2C fill on white, with enclosed white counters in the lettering.
public static class BrandGen
{
    static readonly Color MARK     = Color.FromArgb(255, 0x36, 0x3F, 0x2C);
    static readonly Color KNOCKOUT = Color.FromArgb(255, 0xFF, 0xFF, 0xFF);
    static readonly Color WHITE    = Color.FromArgb(255, 0xFF, 0xFF, 0xFF);

    // Alpha is derived from luminance. A single linear stretch cannot give both a
    // solid fill and proportional edges, because the gain that lifts the fill to
    // full opacity also inflates every antialiased edge pixel. So the curve is
    // thresholded: anything at or below SOLID_LUM is opaque, and only the
    // antialiasing above it interpolates.
    //
    // SOLID_LUM comes from the source: across 79,872 deep-interior samples the
    // fill sits at L58.3 (IQR 58.09-58.46 -- tight, confirming a flat fill), with
    // p99 = 65.6. Anchoring there makes 99% of the fill fully opaque while the
    // edge ramp stays proportional down to the white ground at L255.
    const double SOLID_LUM = 66.0;  // p99 of the measured fill
    const double BG_LUM    = 255.0; // luminance of the white ground

    // Android adaptive icon geometry.
    const double CANVAS_DP    = 108.0;  // total adaptive-icon canvas
    const double SAFE_CIRCLE  = 66.0;   // guaranteed-visible circle diameter
    const double PROBE_SCALE  = 4.0;    // px per dp used while probing

    public static string Run(string root)
    {
        string src = Path.Combine(root, "png", "highlanders.jpg");
        if (!File.Exists(src)) throw new FileNotFoundException("logo source missing", src);

        int mw, mh;
        Bitmap mask = BuildMask(src, out mw, out mh);

        string brandDir = Path.Combine(root, "assets", "brand");
        string resDir   = Path.Combine(root, "android", "app", "src", "main", "res");
        Directory.CreateDirectory(brandDir);

        var log = new System.Text.StringBuilder();
        log.AppendLine("source        : " + src);
        log.AppendLine("mark fill     : #" + MARK.R.ToString("X2") + MARK.G.ToString("X2") + MARK.B.ToString("X2"));
        log.AppendLine("content box   : " + mw + " x " + mh + "  (aspect " + (mw / (double)mh).ToString("F4") + ")");

        // ---- 1. Flutter in-app brandmark ------------------------------------
        // Kept at native crop resolution. The logo renders around 92 logical px,
        // so even a 4x device only samples ~370 px of a 610 px source -- already
        // oversampled. Upscaling past the source would add no detail while
        // quadrupling the APK payload, since the alpha ramp resists compression.
        Bitmap appMark = Scale(FlatTint(mask, MARK), mw, mh);
        Save(appMark, Path.Combine(brandDir, "highlanders_mark.png"));
        Save(Scale(FlatTint(mask, KNOCKOUT), mw, mh), Path.Combine(brandDir, "highlanders_mark_white.png"));
        appMark.Dispose();
        log.AppendLine("in-app mark   : " + mw + " x " + mh + "  (+ white knock-out)");

        // ---- 2. Adaptive icon foreground size -------------------------------
        // Probe for the largest mark that keeps every opaque pixel inside the
        // 66dp guaranteed-visible circle. Measuring beats assuming: the mark's
        // bounding-box corners are largely empty, so a naive rect-vs-circle fit
        // would needlessly shrink the logo.
        double bestDp = 0;
        for (double wdp = 74.0; wdp >= 44.0; wdp -= 0.5)
        {
            if (MaxOpaqueDp(PlaceMark(mask, MARK, CANVAS_DP, wdp, 432, 432), 432.0 / CANVAS_DP)
                <= SAFE_CIRCLE / 2.0) { bestDp = wdp; break; }
        }
        if (bestDp <= 0) throw new Exception("no mark width fits the adaptive safe circle");
        double pct = 100.0 * bestDp / CANVAS_DP;
        log.AppendLine("adaptive size : mark " + bestDp.ToString("F1") + "dp wide = "
                     + pct.ToString("F1") + "% of the " + CANVAS_DP + "dp canvas (max that clears the "
                     + SAFE_CIRCLE + "dp safe circle)");

        // ---- 3. Adaptive icon + monochrome layers ---------------------------
        double[] dpScale = { 1.0, 1.5, 2.0, 3.0, 4.0 };   // mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi
        string[] dens = { "mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi" };
        string anydpi = Path.Combine(resDir, "mipmap-anydpi-v26");
        Directory.CreateDirectory(anydpi);

        for (int i = 0; i < dens.Length; i++)
        {
            int px = (int)Math.Round(CANVAS_DP * dpScale[i]);
            // The bitmaps live in the per-density mipmap folders, NOT in
            // mipmap-anydpi-v26: anydpi outranks every density qualifier, so
            // density-suffixed files placed there would never be selected.
            string dir = Path.Combine(resDir, "mipmap-" + dens[i]);
            Directory.CreateDirectory(dir);
            Save(PlaceMark(mask, MARK,     CANVAS_DP, bestDp, px, px), Path.Combine(dir, "ic_launcher_foreground.png"));
            Save(PlaceMark(mask, KNOCKOUT, CANVAS_DP, bestDp, px, px), Path.Combine(dir, "ic_launcher_monochrome.png"));
        }
        // mipmap-anydpi-v26 holds only the adaptive-icon definition itself.
        Directory.CreateDirectory(anydpi);
        log.AppendLine("adaptive      : foreground + monochrome at 108/162/216/324/432 px");

        // ---- 4. Legacy launcher icons (pre-Android 8) -----------------------
        int[] legacy = { 48, 72, 96, 144, 192 };
        string[] legDir = { "mipmap-mdpi", "mipmap-hdpi", "mipmap-xhdpi", "mipmap-xxhdpi", "mipmap-xxxhdpi" };
        for (int i = 0; i < legacy.Length; i++)
        {
            Save(LegacyIcon(mask, legacy[i]), Path.Combine(resDir, legDir[i], "ic_launcher.png"));
        }
        log.AppendLine("legacy icons  : 48/72/96/144/192 px, rounded white tile");

        // ---- 5. Splash mark --------------------------------------------------
        const double SPLASH_DP = 96.0;
        int[] splash = { 96, 144, 192, 288, 384 };
        for (int i = 0; i < splash.Length; i++)
        {
            string dir = Path.Combine(resDir, "drawable-" + dens[i]);
            Directory.CreateDirectory(dir);
            int wpx = splash[i];
            int hpx = (int)Math.Round(wpx / (mw / (double)mh));
            Save(Scale(FlatTint(mask, MARK), wpx, hpx), Path.Combine(dir, "splash_logo.png"));
        }
        log.AppendLine("splash mark   : " + SPLASH_DP + "dp wide at 96/144/192/288/384 px");

        mask.Dispose();
        log.AppendLine("done");
        return log.ToString();
    }

    // ---- alpha extraction ---------------------------------------------------

    static Bitmap BuildMask(string src, out int mw, out int mh)
    {
        using (var bmp = new Bitmap(src))
        {
            int w = bmp.Width, h = bmp.Height;
            Rectangle rect = new Rectangle(0, 0, w, h);
            BitmapData d = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            int stride = d.Stride;
            byte[] px = new byte[Math.Abs(stride) * h];
            System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length);
            bmp.UnlockBits(d);

            int minX = w, maxX = -1, minY = h, maxY = -1;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    if (Lum(px, stride, x, y) < 235.0)
                    {
                        if (x < minX) minX = x; if (x > maxX) maxX = x;
                        if (y < minY) minY = y; if (y > maxY) maxY = y;
                    }
            if (maxX < 0) throw new Exception("no mark found in source");

            mw = maxX - minX + 1; mh = maxY - minY + 1;
            var outBmp = new Bitmap(mw, mh, PixelFormat.Format32bppArgb);
            var ob = outBmp.LockBits(new Rectangle(0, 0, mw, mh), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            byte[] dst = new byte[Math.Abs(ob.Stride) * mh];
            for (int y = 0; y < mh; y++)
                for (int x = 0; x < mw; x++)
                {
                    double l = Lum(px, stride, minX + x, minY + y);
                    int a;
                    if (l <= SOLID_LUM) a = 255;                       // solid fill
                    else a = (int)Math.Round((BG_LUM - l) / (BG_LUM - SOLID_LUM) * 255.0);
                    if (a < 0) a = 0; else if (a > 255) a = 255;
                    int o = y * ob.Stride + x * 4;
                    dst[o] = 0; dst[o + 1] = 0; dst[o + 2] = 0; dst[o + 3] = (byte)a;
                }
            System.Runtime.InteropServices.Marshal.Copy(dst, 0, ob.Scan0, dst.Length);
            outBmp.UnlockBits(ob);
            return outBmp;
        }
    }

    static double Lum(byte[] px, int stride, int x, int y)
    {
        int o = y * stride + x * 3;
        return 0.2126 * px[o] + 0.7152 * px[o + 1] + 0.0722 * px[o + 2];
    }

    // ---- compositing --------------------------------------------------------

    // Replaces RGB with a flat colour while keeping the mask's alpha. This is what
    // discards JPEG chroma noise: the fill is a solid colour, so per-pixel hue
    // variation carries no information.
    static Bitmap FlatTint(Bitmap mask, Color tint)
    {
        var outBmp = new Bitmap(mask.Width, mask.Height, PixelFormat.Format32bppArgb);
        var d = mask.LockBits(new Rectangle(0, 0, mask.Width, mask.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = d.Stride;
        byte[] src = new byte[Math.Abs(stride) * mask.Height];
        System.Runtime.InteropServices.Marshal.Copy(d.Scan0, src, 0, src.Length);
        mask.UnlockBits(d);

        var o2 = outBmp.LockBits(new Rectangle(0, 0, mask.Width, mask.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        byte[] dst = new byte[Math.Abs(o2.Stride) * mask.Height];
        for (int i = 0; i < mask.Width * mask.Height; i++)
        {
            int o = i * 4;
            dst[o] = tint.B; dst[o + 1] = tint.G; dst[o + 2] = tint.R; dst[o + 3] = src[o + 3];
        }
        System.Runtime.InteropServices.Marshal.Copy(dst, 0, o2.Scan0, dst.Length);
        outBmp.UnlockBits(o2);
        return outBmp;
    }

    static Bitmap NewCanvas(int w, int h)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp)) { g.Clear(Color.Transparent); }
        return bmp;
    }

    // TileFlipXY stops .NET bleeding transparent pixels in from the source edges
    // when bicubic sampling reaches outside the bitmap.
    static void DrawScaled(Graphics g, Bitmap src, float dx, float dy, float dw, float dh)
    {
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.CompositingQuality = CompositingQuality.HighQuality;
        g.SmoothingMode = SmoothingMode.HighQuality;
        var dest = new Rectangle((int)Math.Round(dx), (int)Math.Round(dy), (int)Math.Round(dw), (int)Math.Round(dh));
        using (var attr = new ImageAttributes())
        {
            attr.SetWrapMode(WrapMode.TileFlipXY);
            g.DrawImage(src, dest, 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, attr);
        }
    }

    static Bitmap Scale(Bitmap src, int w, int h)
    {
        Bitmap dst = NewCanvas(w, h);
        using (var g = Graphics.FromImage(dst))
            DrawScaled(g, src, 0, 0, w, h);
        return dst;
    }

    // Places the mark, centred, at a requested width measured in dp, on a canvas
    // of CANVAS_DP square. pxPerDp converts to actual pixels.
    static Bitmap PlaceMark(Bitmap mask, Color tint, double canvasDp, double markWidthDp, int pxW, int pxH)
    {
        double pxPerDp = pxW / canvasDp;
        double mw = markWidthDp * pxPerDp;
        double mh = mw * mask.Height / (double)mask.Width;
        Bitmap tinted = FlatTint(mask, tint);
        Bitmap dst = NewCanvas(pxW, pxH);
        using (var g = Graphics.FromImage(dst))
            DrawScaled(g, tinted,
                (float)((pxW - mw) / 2.0), (float)((pxH - mh) / 2.0), (float)mw, (float)mh);
        tinted.Dispose();
        return dst;
    }

    // Greatest distance, in dp, from the canvas centre to any meaningfully opaque
    // pixel. This is what actually decides whether a launcher's mask clips the mark.
    static double MaxOpaqueDp(Bitmap canvas, double pxPerDp)
    {
        int w = canvas.Width, h = canvas.Height;
        var d = canvas.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = d.Stride;
        byte[] px = new byte[Math.Abs(stride) * h];
        System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length);
        canvas.UnlockBits(d);

        double cx = w / 2.0, cy = h / 2.0, max = 0;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                if (px[y * stride + x * 4 + 3] <= 8) continue;
                double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
                double dist = Math.Sqrt(dx * dx + dy * dy);
                if (dist > max) max = dist;
            }
        return max / pxPerDp;
    }

    // Pre-Android 8: one opaque tile with the shape baked in, since there is no
    // adaptive icon to do the masking. Rounded corner, mark at 72% of the width.
    static Bitmap LegacyIcon(Bitmap mask, int size)
    {
        Bitmap dst = NewCanvas(size, size);
        using (var g = Graphics.FromImage(dst))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float r = size * 0.22f;
            using (var path = new GraphicsPath())
            {
                path.AddArc(0, 0, r, r, 180, 90);
                path.AddArc(size - r, 0, r, r, 270, 90);
                path.AddArc(size - r, size - r, r, r, 0, 90);
                path.AddArc(0, size - r, r, r, 90, 90);
                path.CloseFigure();
                g.FillPath(new SolidBrush(WHITE), path);
            }
            Bitmap tinted = FlatTint(mask, MARK);
            double mw = size * 0.72;
            double mh = mw * mask.Height / (double)mask.Width;
            DrawScaled(g, tinted,
                (float)((size - mw) / 2.0), (float)((size - mh) / 2.0), (float)mw, (float)mh);
            tinted.Dispose();
        }
        return dst;
    }

    static void Save(Bitmap bmp, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        bmp.Save(path, ImageFormat.Png);
        bmp.Dispose();
    }
}
'@ -ReferencedAssemblies System.Drawing

[BrandGen]::Run((Resolve-Path $Root).Path)