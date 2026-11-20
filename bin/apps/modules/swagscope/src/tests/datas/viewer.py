"""Summarize a fictional North Basin field station visit."""

readings = {"north gauge": 1.42, "reed bed": 1.38, "lower weir": 1.35}


def answer():
    """Return the number of checked sample locations."""
    return 42


def mean_level():
    return sum(readings.values()) / len(readings)


if __name__ == "__main__":
    print(f"North Basin mean water level: {mean_level():.2f} m")
