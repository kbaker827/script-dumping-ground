# Monitoring Scripts

Collection of monitoring scripts for events, sports, and entertainment.

## Scripts

### `hurricanes_monitor.py`
Monitors Carolina Hurricanes NHL schedule for new games.

**Usage:**
```bash
python3 hurricanes_monitor.py
```

**Features:**
- Checks NHL API for upcoming Hurricanes games
- Alerts via Telegram when new games are scheduled
- Tracks home vs away games
- Stores known games to avoid duplicates

**Setup:**
Set environment variables:
```bash
export TELEGRAM_BOT_TOKEN="your_token"
export TELEGRAM_CHAT_ID="your_chat_id"
```

---

### `comic_events_monitor.py`
Monitors for comic book conventions and events in North Carolina.

**Usage:**
```bash
python3 comic_events_monitor.py
```

**Features:**
- Tracks major conventions (HeroesCon, Animazement, Supercon, etc.)
- Monitors local comic shop events
- Alerts via Telegram for new events
- Focuses on NC locations: Raleigh, Charlotte, Durham, Greensboro, Asheville, Wilmington

**Tracked Events:**
- Heroes Convention (Charlotte)
- Animazement (Raleigh)
- Raleigh Supercon
- Oak City Comicon
- Charlotte Comicon
- Local comic shop signings and events

**Setup:**
Set environment variables:
```bash
export TELEGRAM_BOT_TOKEN="your_token"
export TELEGRAM_CHAT_ID="your_chat_id"
```

## Data Files

Scripts store known items to avoid duplicate alerts:
- `~/.hurricanes_schedule.json` - Known Hurricanes games
- `~/.comic_events_tracker.json` - Known comic events

## Automation

Add to your heartbeat or cron to run weekly:
```bash
# Example crontab - run every Friday at 9 AM
0 9 * * 5 python3 /path/to/hurricanes_monitor.py
0 9 * * 5 python3 /path/to/comic_events_monitor.py
```

## Requirements

- Python 3.6+
- Internet connection
- Telegram bot token (for notifications)
