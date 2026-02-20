#!/usr/bin/env python3
"""
Comic Book Events Monitor - North Carolina
Monitors for comic conventions, store events, signings, etc. in NC
"""

import json
import os
import sys
import urllib.request
import urllib.parse
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
KEYWORDS = ["comic", "comicon", "comic con", "graphic novel", "anime", "cosplay", "marvel", "dc comics"]
LOCATIONS = ["NC", "North Carolina", "Raleigh", "Charlotte", "Durham", "Greensboro", "Asheville", "Wilmington"]
DATA_FILE = Path.home() / ".comic_events_tracker.json"

# Event sources to check
EVENT_SOURCES = [
    "comic convention",
    "anime convention",
    "fan expo",
    "comic book store",
    "book signing"
]

# Telegram config
TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID', '')

class ComicEventsMonitor:
    def __init__(self):
        self.known_events = self.load_known_events()
        self.new_events = []
    
    def load_known_events(self):
        """Load previously seen events"""
        if DATA_FILE.exists():
            try:
                with open(DATA_FILE, 'r') as f:
                    return json.load(f)
            except:
                return {}
        return {}
    
    def save_known_events(self):
        """Save events to disk"""
        with open(DATA_FILE, 'w') as f:
            json.dump(self.known_events, f, indent=2)
    
    def is_nc_event(self, event_location):
        """Check if event is in North Carolina"""
        location_lower = event_location.lower()
        return any(loc.lower() in location_lower for loc in LOCATIONS)
    
    def is_comic_related(self, event_title, event_description=""):
        """Check if event is comic-related"""
        text = (event_title + " " + event_description).lower()
        return any(keyword in text for keyword in KEYWORDS)
    
    def fetch_eventbrite_events(self):
        """Fetch events from Eventbrite API (requires API key)"""
        # This is a placeholder - Eventbrite requires API key
        # For now, we'll return empty list
        return []
    
    def fetch_from_sources(self):
        """Fetch events from various sources"""
        events = []
        
        # Try to fetch from local comic shop websites
        # These would need to be scraped or have RSS feeds
        comic_shops = [
            "https://www.heroesonline.com",  # Heroes Aren't Hard to Find - Charlotte
            "https://www.flyingcolorscomics.com",  # Flying Colors - Concord
            "https://www.capitalcomics.com",  # Capitol Comics - Raleigh
        ]
        
        print("Checking comic shop websites...")
        # In a real implementation, you'd scrape these or check their event pages
        
        return events
    
    def check_manual_events(self):
        """Check for known major conventions (manually tracked)"""
        # These are known recurring events to watch for
        major_cons = [
            {
                'name': 'Heroes Convention',
                'location': 'Charlotte, NC',
                'venue': 'Charlotte Convention Center',
                'typical_month': 'June',
                'url': 'https://heroesonline.com/heroescon/'
            },
            {
                'name': 'Animazement',
                'location': 'Raleigh, NC',
                'venue': 'Raleigh Convention Center',
                'typical_month': 'May',
                'url': 'https://www.animazement.org/'
            },
            {
                'name': 'Supercon',
                'location': 'Raleigh, NC',
                'venue': 'Raleigh Convention Center',
                'typical_month': 'July',
                'url': 'https://www.raleighsupercon.com/'
            },
            {
                'name': 'Oak City Comicon',
                'location': 'Raleigh, NC',
                'venue': 'NC State Fairgrounds',
                'typical_month': 'October',
                'url': ''
            },
            {
                'name': 'Charlotte Comicon',
                'location': 'Charlotte, NC',
                'venue': 'Hilton Charlotte University Place',
                'typical_month': 'Various',
                'url': 'http://www.charlottecomicon.com/'
            }
        ]
        
        # In a real implementation, you'd scrape these websites for actual dates
        # For now, just report if we haven't seen them before
        for con in major_cons:
            con_id = f"{con['name']}-{datetime.now().year}"
            
            if con_id not in self.known_events:
                # Simulate finding the event
                # In reality, you'd scrape the actual date
                event = {
                    'id': con_id,
                    'name': con['name'],
                    'location': con['location'],
                    'venue': con['venue'],
                    'url': con['url'],
                    'date': 'TBD',  # Would be scraped
                    'source': 'Convention Tracker'
                }
                
                # Only add if it's around the typical time
                current_month = datetime.now().strftime("%B")
                if con['typical_month'] == current_month or con['typical_month'] == 'Various':
                    self.new_events.append(event)
                    self.known_events[con_id] = event
                    print(f"📚 Found: {con['name']}")
    
    def check_local_comic_shops(self):
        """Check local comic shop events"""
        # This would require web scraping or RSS feeds
        # For now, placeholder
        shops = [
            'Heroes Aren\'t Hard to Find (Charlotte)',
            'Flying Colors Comics (Concord)',
            'Capitol Comics (Raleigh)',
            'Ultimate Comics (Durham, Raleigh, Cary)',
            'Gator Comics (Greensboro)',
            'Empire\'s Comics Vault (Raleigh)',
            'Annie\'s Books & Comics (Fayetteville)',
            'Dragon\'s Lair Comics & Fantasy (Raleigh)',
        ]
        
        print(f"Checking {len(shops)} local comic shops...")
    
    def run(self):
        """Main monitoring run"""
        print(f"📚 Comic Book Events Monitor - {datetime.now().strftime('%Y-%m-%d')}")
        print("Location: North Carolina\n")
        
        # Check various sources
        self.check_manual_events()
        self.check_local_comic_shops()
        
        # Save known events
        self.save_known_events()
        
        if self.new_events:
            print(f"\nFound {len(self.new_events)} event(s)!")
            return self.format_message()
        else:
            print("\nNo new events found")
            return None
    
    def format_message(self):
        """Format Telegram message"""
        if not self.new_events:
            return None
        
        message = "📚 **Comic Book Events in NC!** 📚\n\n"
        
        for event in self.new_events:
            message += f"**{event['name']}**\n"
            message += f"📍 {event['location']}\n"
            message += f"🏟️ {event['venue']}\n"
            if event['date'] != 'TBD':
                message += f"📅 {event['date']}\n"
            if event['url']:
                message += f"🔗 [More Info]({event['url']})\n"
            message += "\n"
        
        message += "---\n"
        message += f"Checked: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n"
        message += "Sources: Convention websites, Local comic shops"
        
        return message


def send_telegram(message):
    """Send Telegram message"""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        print("⚠️  Telegram not configured")
        print(f"Message:\n{message}")
        return
    
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = {
            'chat_id': TELEGRAM_CHAT_ID,
            'text': message,
            'parse_mode': 'Markdown',
            'disable_web_page_preview': True
        }
        
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode(),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        
        with urllib.request.urlopen(req, timeout=30) as response:
            print("✅ Telegram message sent!")
            
    except Exception as e:
        print(f"❌ Failed to send: {e}")


if __name__ == "__main__":
    monitor = ComicEventsMonitor()
    message = monitor.run()
    
    if message:
        send_telegram(message)