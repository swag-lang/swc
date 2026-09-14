module raytrace;

import common;
immutable s64 W  = 480;
immutable s64 H  = 360;
immutable u64 NS = 4;

immutable double[4] SCX  = [0.0, 2.0, -2.0, 0.0];
immutable double[4] SCY  = [-0.5, 0.0, 0.0, -5001.0];
immutable double[4] SCZ  = [3.0, 4.5, 4.0, 0.0];
immutable double[4] SRAD = [1.0, 1.0, 1.0, 5000.0];
immutable double[4] SR   = [1.0, 0.2, 0.2, 0.9];
immutable double[4] SG   = [0.25, 1.0, 0.3, 0.85];
immutable double[4] SB   = [0.25, 0.3, 1.0, 0.3];
immutable double[4] SRE  = [0.35, 0.45, 0.55, 0.15];

immutable double LX  = 5.0;
immutable double LY  = 5.0;
immutable double LZ  = -3.0;
immutable double AMB = 0.12;

__gshared double g_HitT = 0.0;
__gshared s32    g_HitI = -1;

__gshared double g_OutR = 0.0;
__gshared double g_OutG = 0.0;
__gshared double g_OutB = 0.0;

void intersect(double ox, double oy, double oz, double dx, double dy, double dz, double tmin)
{
    double best = 1.0e30;
    s32    hit  = -1;

    for (u64 i = 0; i < NS; i++)
    {
        double ex   = ox - SCX[i];
        double ey   = oy - SCY[i];
        double ez   = oz - SCZ[i];
        double b    = 2.0 * (ex * dx + ey * dy + ez * dz);
        double c    = ex * ex + ey * ey + ez * ez - SRAD[i] * SRAD[i];
        double disc = b * b - 4.0 * c;
        if (disc < 0.0)
            continue;

        double sq = sqrt(disc);
        double t  = (-b - sq) * 0.5;
        if (t < tmin)
            t = (-b + sq) * 0.5;
        if (t >= tmin && t < best)
        {
            best = t;
            hit  = cast(s32) i;
        }
    }

    g_HitT = best;
    g_HitI = hit;
}

void trace(double ox, double oy, double oz, double dx, double dy, double dz, s32 depth)
{
    intersect(ox, oy, oz, dx, dy, dz, 0.0001);
    double t   = g_HitT;
    s32    hit = g_HitI;
    if (hit < 0)
    {
        g_OutR = 0.05;
        g_OutG = 0.07;
        g_OutB = 0.12;
        return;
    }

    u64    hi = cast(u64) hit;
    double px = ox + dx * t;
    double py = oy + dy * t;
    double pz = oz + dz * t;
    double nl = 1.0 / SRAD[hi];
    double nx = (px - SCX[hi]) * nl;
    double ny = (py - SCY[hi]) * nl;
    double nz = (pz - SCZ[hi]) * nl;

    double lx = LX - px;
    double ly = LY - py;
    double lz = LZ - pz;
    double ll = 1.0 / sqrt(lx * lx + ly * ly + lz * lz);
    lx *= ll;
    ly *= ll;
    lz *= ll;

    double lam = nx * lx + ny * ly + nz * lz;
    if (lam < 0.0)
    {
        lam = 0.0;
    }
    else
    {
        intersect(px, py, pz, lx, ly, lz, 0.001);
        if (g_HitI >= 0)
            lam = 0.0;
    }

    double k  = AMB + 0.88 * lam;
    double cr = SR[hi] * k;
    double cg = SG[hi] * k;
    double cb = SB[hi] * k;

    double refl = SRE[hi];
    if (refl > 0.0 && depth < 2)
    {
        double d = 2.0 * (dx * nx + dy * ny + dz * nz);
        trace(px, py, pz, dx - d * nx, dy - d * ny, dz - d * nz, depth + 1);
        cr = cr * (1.0 - refl) + g_OutR * refl;
        cg = cg * (1.0 - refl) + g_OutG * refl;
        cb = cb * (1.0 - refl) + g_OutB * refl;
    }

    g_OutR = cr;
    g_OutG = cg;
    g_OutB = cb;
}

int main()
{
    double t0 = now();

    double aspect = cast(double) W / cast(double) H;
    u64    check  = 0;

    for (s64 py = 0; py < H; py++)
    {
        for (s64 px = 0; px < W; px++)
        {
            double dx = ((cast(double) px + 0.5) / cast(double) W * 2.0 - 1.0) * aspect;
            double dy = 1.0 - (cast(double) py + 0.5) / cast(double) H * 2.0;
            double dz = 1.0;
            double il = 1.0 / sqrt(dx * dx + dy * dy + dz * dz);
            trace(0.0, 0.0, 0.0, dx * il, dy * il, dz * il, 0);

            s64 ir = cast(s64) (g_OutR * 255.0);
            s64 ig = cast(s64) (g_OutG * 255.0);
            s64 ib = cast(s64) (g_OutB * 255.0);
            if (ir > 255)
                ir = 255;
            if (ig > 255)
                ig = 255;
            if (ib > 255)
                ib = 255;
            check += cast(u64) (ir + 2 * ig + 3 * ib);
        }
    }

    double t1 = now();
    report(check, t0, t1);
    return 0;
}
