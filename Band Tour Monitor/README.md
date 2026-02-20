# Band Tour Date Monitor

Monitors concert tour dates for **Metallica**, **Green Day**, and **Five Finger Death Punch** in **North Carolina** and sends alerts via Telegram.

## Features

- 🎸 Tracks Metallica, Green Day, and Five Finger Death Punch tour announcements
- 📍 Filters for shows in North Carolina only
- 🤖 Sends Telegram notifications for new shows
- 💾 Remembers shows it's already seen (no duplicate alerts)
- 🔍 Uses Bandsintown API (free, no API key needed)

## Quick Start

### 1. Setup Telegram

Run the setup wizard:
```bash
python3 band_tour_monitor.py --setup
```

Or set environment variables:
```bash
export TELEGRAM_BOT_TOKEN="your_bot_token_here"
export TELEGRAM_CHAT_ID="your_chat_id_here"
```

**How to get credentials:**
- **Bot Token**: Message [@BotFather](https://t.me/botfather) on Telegram, send `/newbot`
- **Chat ID**: Message [@userinfobot](https://t.me/userinfobot) on Telegram

### 2. Test It

```bash
python3 band_tour_monitor.py --test
```

This sends a test message to verify Telegram is working.

### 3. Run It

```bash
python3 band_tour_monitor.py
```

## Running Automatically

### Option A: OpenClaw Heartbeat (Recommended)

Add to your `HEARTBEAT.md`:
```markdown
## Band Tour Monitor
Check for new concerts once daily (~1x per day):
- Command: `python3 /path/to/band_tour_monitor.py`
- Alert Kyle when new shows found
```

### Option B: Cron Job (Linux/Mac)

```bash
# Edit crontab
crontab -e

# Add line to run daily at 9 AM:
0 9 * * * /path/to/run_band_monitor.sh

# Or every 6 hours:
0 */6 * * * /path/to/run_band_monitor.sh
```

### Option C: Scheduled Task (Windows)

```powershell
# Create task to run daily
schtasks /create /tn "BandTourMonitor" /tr "python C:\path\to\band_tour_monitor.py" /sc daily /st 09:00
```

## How It Works

1. **Fetches** upcoming shows from Bandsintown API for each band
2. **Filters** for venues in North Carolina
3. **Compares** against known shows (stored in `~/.band_tour_tracker.json`)
4. **Alerts** via Telegram when new shows are found
5. **Saves** new shows to avoid duplicate notifications

## File Locations

- **Script**: `band_tour_monitor.py`
- **Known Shows**: `~/.band_tour_tracker.json`
- **Telegram Config**: `~/.band_tour_config.json`

## Customization

### Change Bands

Edit the `BANDS` list in `band_tour_monitor.py`:
```python
BANDS = ["Metallica", "Green Day", "Your Band Here"]
```

### Change Location

Edit the state filter:
```python
STATE_FILTER = "NC"  # Change to your state code
STATE_FULL = "North Carolina"  # Change to your state name
```

### Add More States

Modify the `is_in_north_carolina()` method to check multiple states:
```python
def is_in_target_region(self, venue, city, region):
    location_text = f"{venue} {city} {region}".lower()
    states = [' nc', ' sc', ' va', ' tn']  # NC and neighbors
    return any(state in location_text for state in states)
```

## Example Output

When new shows are found, you'll get a Telegram message like:

```
🎸 **New Concert Announcements!** 🎸

**Metallica**
📍 PNC Arena
🌆 Raleigh, NC
📅 Friday, August 15, 2025 at 07:30 PM
🔗 [Get Tickets](https://www.bandsintown.com/...)

---
Checked: 2025-02-19 09:00
```

## Requirements

- Python 3.6+
- Internet connection
- Telegram bot token and chat ID

## No New Shows?

If no new shows are found, the script outputs:
```
✓ No new shows found
```

And doesn't send a Telegram message (to avoid spam).

## Troubleshooting

### "Telegram credentials not set"

Run setup: `python3 band_tour_monitor.py --setup`

### No shows found for a band

The band might not have any upcoming shows listed on Bandsintown, or they might not be playing in NC.

### Script errors

Check your Python version:
```bash
python3 --version  # Should be 3.6 or higher
```

### Want to reset known shows?

Delete the tracker file:
```bash
rm ~/.band_tour_tracker.json
```

This will cause all current shows to be reported as "new" on the next run.

## API Limits

Bandsintown API has generous rate limits for basic usage. If you start hitting limits:
- Reduce check frequency (e.g., daily instead of hourly)
- Add delays between band requests

## License

MIT License — Modify and share freely!

## Credits

- Concert data: [Bandsintown API](https://artists.bandsintown.com/support/api)
- Notifications: Telegram Bot API