from datetime import datetime

import requests
import yaml

URLS = [
    "https://api.github.com",
    "https://google.com",
    "https://httpstat.us/503",   # celowo "zepsuty" endpoint do demonstracji DOWN
]
WEATHER_URL = "https://wttr.in/Dublin?format=j1"
REPORT_FILE = "daily_report.yaml"


def check_service(url):
    """Zwraca status uslugi: UP gdy odpowiada kodem < 400."""
    try:
        response = requests.get(url, timeout=5)
        if response.status_code < 400:
            return f"🟢 UP ({response.status_code})"
        return f"🔴 DOWN ({response.status_code})"
    except requests.RequestException as e:
        return f"🔴 DOWN ({type(e).__name__})"


def get_weather():
    """Pobiera aktualna temperature dla Dublina z wttr.in."""
    try:
        response = requests.get(WEATHER_URL, timeout=10)
        response.raise_for_status()
        data = response.json()
        current = data["current_condition"][0]
        return {
            "region": "Dublin",
            "temperature_c": int(current["temp_C"]),
            "feels_like_c": int(current["FeelsLikeC"]),
            "description": current["weatherDesc"][0]["value"],
        }
    except (requests.RequestException, KeyError, ValueError) as e:
        return {"region": "Dublin", "error": f"{type(e).__name__}: {e}"}


def main():
    report = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "services_status": {url: check_service(url) for url in URLS},
        "environment_info": get_weather(),
    }

    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        yaml.dump(report, f, allow_unicode=True, sort_keys=False)

    print(f"Raport zapisany do {REPORT_FILE}:\n")
    print(yaml.dump(report, allow_unicode=True, sort_keys=False))


if __name__ == "__main__":
    main()
