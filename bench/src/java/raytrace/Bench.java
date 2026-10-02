class Bench
{
    static final long W = 480;
    static final long H = 360;
    static final int NS = 4;

    static final double[] SCX = { 0.0, 2.0, -2.0, 0.0 };
    static final double[] SCY = { -0.5, 0.0, 0.0, -5001.0 };
    static final double[] SCZ = { 3.0, 4.5, 4.0, 0.0 };
    static final double[] SRAD = { 1.0, 1.0, 1.0, 5000.0 };
    static final double[] SR = { 1.0, 0.2, 0.2, 0.9 };
    static final double[] SG = { 0.25, 1.0, 0.3, 0.85 };
    static final double[] SB = { 0.25, 0.3, 1.0, 0.3 };
    static final double[] SRE = { 0.35, 0.45, 0.55, 0.15 };

    static final double LX = 5.0;
    static final double LY = 5.0;
    static final double LZ = -3.0;
    static final double AMB = 0.12;

    static double gHitT = 0.0;
    static int gHitI = -1;

    static double gOutR = 0.0;
    static double gOutG = 0.0;
    static double gOutB = 0.0;

    static void intersect(double ox, double oy, double oz, double dx, double dy, double dz, double tmin)
    {
        double best = 1.0e30;
        int hit = -1;

        for (int i = 0; i < NS; i++)
        {
            double ex = ox - SCX[i];
            double ey = oy - SCY[i];
            double ez = oz - SCZ[i];
            double b = 2.0 * (ex * dx + ey * dy + ez * dz);
            double c = ex * ex + ey * ey + ez * ez - SRAD[i] * SRAD[i];
            double disc = b * b - 4.0 * c;
            if (disc < 0.0)
                continue;

            double sq = Math.sqrt(disc);
            double t = (-b - sq) * 0.5;
            if (t < tmin)
                t = (-b + sq) * 0.5;
            if (t >= tmin && t < best)
            {
                best = t;
                hit = i;
            }
        }

        gHitT = best;
        gHitI = hit;
    }

    static void trace(double ox, double oy, double oz, double dx, double dy, double dz, int depth)
    {
        intersect(ox, oy, oz, dx, dy, dz, 0.0001);
        double t = gHitT;
        int hit = gHitI;
        if (hit < 0)
        {
            gOutR = 0.05;
            gOutG = 0.07;
            gOutB = 0.12;
            return;
        }

        int hi = hit;
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
        double ll = 1.0 / Math.sqrt(lx * lx + ly * ly + lz * lz);
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
            if (gHitI >= 0)
                lam = 0.0;
        }

        double k = AMB + 0.88 * lam;
        double cr = SR[hi] * k;
        double cg = SG[hi] * k;
        double cb = SB[hi] * k;

        double refl = SRE[hi];
        if (refl > 0.0 && depth < 2)
        {
            double d = 2.0 * (dx * nx + dy * ny + dz * nz);
            trace(px, py, pz, dx - d * nx, dy - d * ny, dz - d * nz, depth + 1);
            cr = cr * (1.0 - refl) + gOutR * refl;
            cg = cg * (1.0 - refl) + gOutG * refl;
            cb = cb * (1.0 - refl) + gOutB * refl;
        }

        gOutR = cr;
        gOutG = cg;
        gOutB = cb;
    }

    public static void main(String[] args)
    {
        long startTime = System.nanoTime();

        double aspect = (double) W / (double) H;
        long check = 0;

        for (long py = 0; py < H; py++)
        {
            for (long px = 0; px < W; px++)
            {
                double dx = (((double) px + 0.5) / (double) W * 2.0 - 1.0) * aspect;
                double dy = 1.0 - ((double) py + 0.5) / (double) H * 2.0;
                double dz = 1.0;
                double il = 1.0 / Math.sqrt(dx * dx + dy * dy + dz * dz);
                trace(0.0, 0.0, 0.0, dx * il, dy * il, dz * il, 0);

                long ir = (long) (gOutR * 255.0);
                long ig = (long) (gOutG * 255.0);
                long ib = (long) (gOutB * 255.0);
                if (ir > 255)
                    ir = 255;
                if (ig > 255)
                    ig = 255;
                if (ib > 255)
                    ib = 255;
                check += (long) (ir + 2 * ig + 3 * ib);
            }
        }

        double ms = (System.nanoTime() - startTime) * 1000.0 / 1_000_000_000.0;
        System.out.printf(java.util.Locale.ROOT, "CHECK=%d MS=%.6f%n", check, ms);
        return;
    }
}
