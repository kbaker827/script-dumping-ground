#!/usr/bin/env python3
"""
Band Tour Date Monitor for Telegram
Monitors Bandsintown API for concert dates and sends Telegram alerts

Tracks: Metallica, Green Day
Location: North Carolina, USA
"""

import json
import os
import sys
import urllib.request
import urllib.parse
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
BANDS = ["Metallica", "Green Day"]
STATE_FILTER = "NC"  # North Carolina
STATE_FULL = "North Carolina"
DATA_FILE = Path.home() / ".band_tour_tracker.json"

# Bandsintown API (free tier - no API key needed for basic queries)
# Format: https://rest.bandsintown.com/artists/{artist}/events?app_id=your_app_id
APP_ID = "band_tour_monitor_001"

class TourMonitor:
    def __init__(self):
        self.known_shows = self.load_known_shows()
        self.new_shows = []
        
    def load_known_shows(self):
        """Load previously seen shows from disk"""
        if DATA_FILE.exists():
            try:
                with open(DATA_FILE, 'r') as f:
                    return json.load(f)
            except:
                return {}
        return {}
    
    def save_known_shows(self):
        """Save seen shows to disk"""
        with open(DATA_FILE, 'w') as f:
            json.dump(self.known_shows, f, indent=2)
    
    def fetch_shows(self, band):
        """Fetch upcoming shows for a band"""
        try:
            # URL encode the band name
            encoded_band = urllib.parse.quote(band)
            url = f"https://rest.bandsintown.com/artists/{encoded_band}/events?app_id={APP_ID}"
            
            req = urllib.request.Request(
                url,
                headers={
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            )
            
            with urllib.request.urlopen(req, timeout=30) as response:
                data = json.loads(response.read().decode('utf-8'))
                return data if isinstance(data, list) else []
                
        except Exception as e:
            print(f"Error fetching shows for {band}: {e}")
            return []
    
    def is_in_north_carolina(self, venue, city, region):
        """Check if location is in North Carolina"""
        location_text = f"{venue} {city} {region}".lower()
        
        # Check various ways NC might be listed
        nc_indicators = [
            ', nc',
            ',nc',
            'north carolina',
            ' nc ',
            ' nc,',
        ]
        
        for indicator in nc_indicators:
            if indicator in location_text:
                return True
        
        # Check if region field matches
        if region and ('nc' in region.lower() or 'north carolina' in region.lower()):
            return True
            
        return False
    
    def check_band(self, band):
        """Check for new shows for a specific band"""
        print(f"Checking shows for {band}...")
        shows = self.fetch_shows(band)
        
        for show in shows:
            try:
                venue_data = show.get('venue', {})
                venue_name = venue_data.get('name', 'Unknown Venue')
                city = venue_data.get('city', '')
                region = venue_data.get('region', '')  # State code
                country = venue_data.get('country', '')
                
                # Skip if not in NC
                if not self.is_in_north_carolina(venue_name, city, region):
                    continue
                
                # Build unique show ID
                show_id = show.get('id') or f"{band}-{show.get('datetime', '')}-{venue_name}"
                
                # Check if we've seen this show before
                if show_id in self.known_shows:
                    continue
                
                # New show found!
                show_info = {
                    'band': band,
                    'venue': venue_name,
                    'city': city,
                    'region': region,
                    'date': show.get('datetime', 'TBD'),
                    'url': show.get('url', ''),
                    'show_id': show_id
                }
                
                self.new_shows.append(show_info)
                self.known_shows[show_id] = show_info
                
                print(f"  🎵 NEW SHOW: {band} at {venue_name} in {city}, {region}")
                
            except Exception as e:
                print(f"Error processing show: {e}")
                continue
    
    def format_telegram_message(self):
        """Format new shows for Telegram message"""
        if not self.new_shows:
            return None
        
        message = "🎸 **New Concert Announcements!** 🎸\n\n"
        
        for show in self.new_shows:
            # Format date nicely
            date_str = show['date']
            try:
                if 'T' in date_str:
                    dt = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
                    date_str = dt.strftime("%A, %B %d, %Y at %I:%M %p")
                else:
                    date_str = date_str
            except:
                pass
            
            message += f"**{show['band']}**\n"
            message += f"📍 {show['venue']}\n"
            message += f"🌆 {show['city']}, {show['region']}\n"
            message += f"📅 {date_str}\n"
            if show['url']:
                message += f"🔗 [Get Tickets]({show['url']})\n"
            message += "\n"
        
        message += "---\n"
        message += f"Checked: {datetime.now().strftime('%Y-%m-%d %H:%M')}"
        
        return message
    
    def run(self):
        """Main monitoring run"""
        print(f"🎸 Band Tour Monitor - {datetime.now().strftime('%Y-%m-%d %H:%M')}")
        print(f"Tracking: {', '.join(BANDS)}")
        print(f"Location: {STATE_FULL}\n")
        
        # Check each band
        for band in BANDS:
            self.check_band(band)
        
        # Save updated known shows
        self.save_known_shows()
        
        # Report results
        if self.new_shows:
            print(f"\n✅ Found {len(self.new_shows)} new show(s)!")
            message = self.format_telegram_message()
            return message
        else:
            print("\n✓ No new shows found")
            return None


def send_telegram_message(message, bot_token=None, chat_id=None):
    """Send message via Telegram"""
    # Try to get from environment if not provided
    bot_token = bot_token or os.environ.get('TELEGRAM_BOT_TOKEN')
    chat_id = chat_id or os.environ.get('TELEGRAM_CHAT_ID')
    
    if not bot_token or not chat_id:
        print("⚠️  Telegram credentials not set. Message not sent.")
        print("Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID environment variables")
        print("\nMessage that would have been sent:")
        print("=" * 50)
        print(message)
        print("=" * 50)
        return False
    
    try:
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        
        data = {
            'chat_id': chat_id,
            'text': message,
            'parse_mode': 'Markdown',
            'disable_web_page_preview': False
        }
        
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        
        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode('utf-8'))
            if result.get('ok'):
                print("✅ Telegram message sent successfully!")
                return True
            else:
                print(f"❌ Telegram API error: {result}")
                return False
                
    except Exception as e:
        print(f"❌ Failed to send Telegram message: {e}")
        return False


def setup_telegram():
    """Interactive setup for Telegram credentials"""
    print("\n📱 Telegram Setup")
    print("=" * 50)
    print("\nTo get your Bot Token:")
    print("1. Message @BotFather on Telegram")
    print("2. Send /newbot and follow instructions")
    print("3. Copy the bot token (looks like: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz)")
    print("\nTo get your Chat ID:")
    print("1. Message @userinfobot on Telegram")
    print("2. It will reply with your Chat ID")
    print("=" * 50)
    
    token = input("\nEnter Bot Token: ").strip()
    chat_id = input("Enter Chat ID: ").strip()
    
    # Save to config file
    config_file = Path.home() / ".band_tour_config.json"
    config = {
        'bot_token': token,
        'chat_id': chat_id
    }
    
    with open(config_file, 'w') as f:
        json.dump(config, f)
    
    print(f"✅ Configuration saved to {config_file}")
    print("\nYou can also set environment variables:")
    print(f"export TELEGRAM_BOT_TOKEN='{token}'")
    print(f"export TELEGRAM_CHAT_ID='{chat_id}'")


def load_telegram_config():
    """Load Telegram config from file if exists"""
    config_file = Path.home() / ".band_tour_config.json"
    if config_file.exists():
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
                os.environ['TELEGRAM_BOT_TOKEN'] = config.get('bot_token', '')
                os.environ['TELEGRAM_CHAT_ID'] = config.get('chat_id', '')
                return True
        except:
            pass
    return False


def main():
    """Main entry point"""
    # Handle command line arguments
    if len(sys.argv) > 1:
        if sys.argv[1] == '--setup':
            setup_telegram()
            return
        elif sys.argv[1] == '--test':
            # Send test message
            load_telegram_config()
            send_telegram_message(
                "🎸 **Test Message**\n\n"
                "Your band tour monitor is working!\n"
                "You'll receive notifications when Metallica or Green Day announce shows in NC."
            )
            return
    
    # Load config if available
    load_telegram_config()
    
    # Run monitor
    monitor = TourMonitor()
    message = monitor.run()
    
    # Send notification if new shows found
    if message:
        send_telegram_message(message)
    
    print("\nDone!")


if __name__ == "__main__":
    main()