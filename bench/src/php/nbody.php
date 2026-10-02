<?php
const STEPS = 500000;
const PI = 3.141592653589793;
const SOLAR_MASS = ((4.0 * PI) * PI);
const DAYS_PER_YEAR = 365.24;
class Body {
    public $x;
    public $y;
    public $z;
    public $vx;
    public $vy;
    public $vz;
    public $mass;

    function __construct($x, $y, $z, $vx, $vy, $vz, $mass) {
        $this->x = $x;
        $this->y = $y;
        $this->z = $z;
        $this->vx = $vx;
        $this->vy = $vy;
        $this->vz = $vz;
        $this->mass = $mass;
    }

}

function offset_momentum($bodies) {
    $px = 0.0;
    $py = 0.0;
    $pz = 0.0;
    foreach ($bodies as $b) {
        $px += ($b->vx * $b->mass);
        $py += ($b->vy * $b->mass);
        $pz += ($b->vz * $b->mass);
    }
    $bodies[0]->vx = ((-$px) / SOLAR_MASS);
    $bodies[0]->vy = ((-$py) / SOLAR_MASS);
    $bodies[0]->vz = ((-$pz) / SOLAR_MASS);
}

function advance($bodies, $dt) {
    $nb = count($bodies);
    for ($i = 0; $i < $nb; $i += 1) {
        $bi = $bodies[$i];
        for ($j = ($i + 1); $j < $nb; $j += 1) {
            $bj = $bodies[$j];
            $dx = ($bi->x - $bj->x);
            $dy = ($bi->y - $bj->y);
            $dz = ($bi->z - $bj->z);
            $d2 = ((($dx * $dx) + ($dy * $dy)) + ($dz * $dz));
            $mag = ($dt / ($d2 * sqrt($d2)));
            $bi->vx -= (($dx * $bj->mass) * $mag);
            $bi->vy -= (($dy * $bj->mass) * $mag);
            $bi->vz -= (($dz * $bj->mass) * $mag);
            $bj->vx += (($dx * $bi->mass) * $mag);
            $bj->vy += (($dy * $bi->mass) * $mag);
            $bj->vz += (($dz * $bi->mass) * $mag);
        }
    }
    foreach ($bodies as $b) {
        $b->x += ($dt * $b->vx);
        $b->y += ($dt * $b->vy);
        $b->z += ($dt * $b->vz);
    }
}

function energy($bodies) {
    $e = 0.0;
    $nb = count($bodies);
    for ($i = 0; $i < $nb; $i += 1) {
        $bi = $bodies[$i];
        $e += ((0.5 * $bi->mass) * ((($bi->vx * $bi->vx) + ($bi->vy * $bi->vy)) + ($bi->vz * $bi->vz)));
        for ($j = ($i + 1); $j < $nb; $j += 1) {
            $bj = $bodies[$j];
            $dx = ($bi->x - $bj->x);
            $dy = ($bi->y - $bj->y);
            $dz = ($bi->z - $bj->z);
            $e -= (($bi->mass * $bj->mass) / sqrt(((($dx * $dx) + ($dy * $dy)) + ($dz * $dz))));
        }
    }
    return $e;
}

$bodies = [new Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS), new Body(4.84143144246472090e+00, (-1.16032004402742839e+00), (-1.03622044471123109e-01), (1.66007664274403694e-03 * DAYS_PER_YEAR), (7.69901118419740425e-03 * DAYS_PER_YEAR), ((-6.90460016972063023e-05) * DAYS_PER_YEAR), (9.54791938424326609e-04 * SOLAR_MASS)), new Body(8.34336671824457987e+00, 4.12479856412430479e+00, (-4.03523417114321381e-01), ((-2.76742510726862411e-03) * DAYS_PER_YEAR), (4.99852801234917238e-03 * DAYS_PER_YEAR), (2.30417297573763929e-05 * DAYS_PER_YEAR), (2.85885980666130812e-04 * SOLAR_MASS)), new Body(1.28943695621391310e+01, (-1.51111514016986312e+01), (-2.23307578892655734e-01), (2.96460137564761618e-03 * DAYS_PER_YEAR), (2.37847173959480950e-03 * DAYS_PER_YEAR), ((-2.96589568540237556e-05) * DAYS_PER_YEAR), (4.36624404335156298e-05 * SOLAR_MASS)), new Body(1.53796971148509165e+01, (-2.59193146099879641e+01), 1.79258772950371181e-01, (2.68067772490389322e-03 * DAYS_PER_YEAR), (1.62824170038242295e-03 * DAYS_PER_YEAR), ((-9.51592254519715870e-05) * DAYS_PER_YEAR), (5.15138902046611451e-05 * SOLAR_MASS))];

// Timed work; input generation above is excluded.
$t0 = hrtime(true) / 1e9;
offset_momentum($bodies);
for ($s = 0; $s < STEPS; $s += 1) {
    advance($bodies, 0.01);
}
$e = energy($bodies);
$check = floor(((-$e) * 1e12));
$t1 = hrtime(true) / 1e9;
echo sprintf("CHECK=%d MS=%.3f", $check, (($t1 - $t0) * 1000.0)) . "\n";
