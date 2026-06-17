import json
import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import urllib.request
import urllib.error


TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
KST = ZoneInfo("Asia/Seoul")


def format_event_time(event_time: str) -> str:
    if not event_time or event_time == "unknown":
        return "unknown"

    try:
        normalized = event_time.replace("Z", "+00:00")
        dt = datetime.fromisoformat(normalized)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(KST).strftime("%Y-%m-%d %H:%M:%S %Z")
    except ValueError:
        return event_time


def send_discord(message: str):
    if not DISCORD_WEBHOOK_URL:
        print("DISCORD_WEBHOOK_URL is empty")
        return

    data = json.dumps({
        # Discord content 제한 대비
        "content": message[:1900]
    }).encode("utf-8")

    req = urllib.request.Request(
        DISCORD_WEBHOOK_URL,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "aws-lambda-asg-notifier"
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as res:
            print("Discord response:", res.status)

    except urllib.error.HTTPError as e:
        print("Discord HTTPError:", e.code)
        print("Discord response body:", e.read().decode("utf-8", errors="ignore"))

    except Exception as e:
        print("Discord send failed:", repr(e))


def send_telegram(message: str):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        print("Telegram env is empty")
        return

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"

    data = json.dumps({
        "chat_id": TELEGRAM_CHAT_ID,
        "text": message[:3900],
    }).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "aws-lambda-asg-notifier"
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as res:
            print("Telegram response:", res.status)

    except urllib.error.HTTPError as e:
        print("Telegram HTTPError:", e.code)
        print("Telegram response body:", e.read().decode("utf-8", errors="ignore"))

    except Exception as e:
        print("Telegram send failed:", repr(e))


def lambda_handler(event, context):
    print("Received event:", json.dumps(event, ensure_ascii=False))

    detail_type = event.get("detail-type", "unknown")
    detail = event.get("detail", {})

    asg_name = detail.get("AutoScalingGroupName", "unknown")
    instance_id = detail.get("EC2InstanceId", "unknown")
    cause = detail.get("Cause", "")
    event_time = format_event_time(event.get("time", "unknown"))
    region = event.get("region", "unknown")

    if "Launch Successful" in detail_type:
        title = "[AUTO SCALING] 인스턴스 생성 성공"
    elif "Launch Unsuccessful" in detail_type:
        title = "[AUTO SCALING] 인스턴스 생성 실패"
    elif "Terminate Successful" in detail_type:
        title = "[AUTO SCALING] 인스턴스 종료 성공"
    elif "Terminate Unsuccessful" in detail_type:
        title = "[AUTO SCALING] 인스턴스 종료 실패"
    else:
        title = "[AWS Auto Scaling Event]"

    message = f"""
{title}

Event: {detail_type}
ASG: {asg_name}
Instance: {instance_id}
Region: {region}
Time: {event_time}

Cause:
{cause}
"""

    send_discord(message)
    send_telegram(message)

    return {
        "statusCode": 200,
        "body": json.dumps({"result": "ok"})
    }
