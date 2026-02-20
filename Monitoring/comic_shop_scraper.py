#!/usr/bin/env python3
"""
Local Comic Shop Event Scraper - North Carolina
Scrapes individual comic shop websites for events and signings
"""

import json
import os
import sys
import urllib.request
import urllib.error
import re
from datetime import datetime
from pathlib import Path

# Configuration
DATA_FILE = Path.home() / ".comic_shop_events.json"
TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID', '')

# NC Comic Shops to monitor
COMIC_SHOPS = [
    {
        'name': "Heroes Aren't Hard to Find",
        'location': 'Charlotte, NC',
        'url': 'https://heroesonline.com/events/',
        'type': 'html',
        'selector': r'class="event"|class="tribe-events'  # Basic pattern matching
    },
    {
        'name': 'Flying Colors Comics',
        'location': 'Concord, NC',
        'url': 'https://www.flyingcolorscomics.com/events',
        'type': 'html',
        'selector': r'event|signing|appearance'
    },
    {
        'name': 'Capitol Comics',
        'location': 'Raleigh, NC',
        'url': 'https://www.capitalcomics.com/events',
        'type': 'html',
        'selector': r'event|signing'
    },
    {
        'name': 'Ultimate Comics',
        'location': 'Durham, Raleigh, Cary, NC',
        'url': 'https://www.ultimatecomics.com/events/',
        'type': 'html',
        'selector': r'event|signing|release'
    },
    {
        'name': "Empire's Comics Vault",
        'location': 'Raleigh, NC',
        'url': 'https://empirescomicsvault.com/events/',
        'type': 'html',
        'selector': r'event|signing'
    },
    {
        'name': 'Gator Comics',
        'location': 'Greensboro, NC',
        'url': 'https://www.gatorcomics.com/events',
        'type': 'html',
        'selector': r'event|signing'
    },
    {
        'name': "Annie's Books & Comics",
        'location': 'Fayetteville, NC',
        'url': 'https://www.anniesbookscomics.com/events',
        'type': 'html',
        'selector': r'event|signing'
    },
    {
        'name': "Dragon's Lair Comics",
        'location': 'Raleigh, NC',
        'url': 'https://www.dragonslaircomics.com/events',
        'type': 'html',
        'selector': r'event|signing|game'
    }
]

class ComicShopScraper:
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
    
    def fetch_page(self, url):
        """Fetch webpage content"""
        try:
            req = urllib.request.Request(
                url,
                headers={
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            )
            
            with urllib.request.urlopen(req, timeout=30) as response:
                return response.read().decode('utf-8', errors='ignore')
                
        except Exception as e:
            print(f"Error fetching {url}: {e}")
            return None
    
    def extract_events(self, html, shop):
        """Extract events from HTML (basic implementation)"""
        events = []
        
        if not html:
            return events
        
        # Look for common event patterns
        # This is a simplified scraper - real implementation would use BeautifulSoup
        html_lower = html.lower()
        
        # Check if page contains event indicators
        has_events = any(keyword in html_lower for keyword in 
                        ['event', 'signing', 'appearance', 'release party', 'game night'])
        
        if has_events:
            # Try to extract event titles and dates
            # Look for patterns like "Month Day - Event Name"
            date_patterns = [
                r'(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}[^\n]*signing[^\n]*',
                r'(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}[^\n]*event[^\n]*',
                r'\d{1,2}/\d{1,2}/\d{2,4}[^\n]*signing[^\n]*',
                r'\d{1,2}/\d{1,2}/\d{2,4}[^\n]*event[^\n]*'
            ]
            
            for pattern in date_patterns:
                matches = re.findall(pattern, html, re.IGNORECASE)
                for match in matches:
                    event_id = f"{shop['name']}-{match}"
                    
                    if event_id not in self.known_events:
                        event = {
                            'id': event_id,
                            'shop': shop['name'],
                            'location': shop['location'],
                            'title': match.strip(),
                            'url': shop['url'],
                            'found_date': datetime.now().isoformat()
                        }
                        events.append(event)
                        self.known_events[event_id] = event
        
        return events
    
    def check_shop(self, shop):
        """Check a single shop for events"""
        print(f"Checking {shop['name']}...")
        
        html = self.fetch_page(shop['url'])
        if html:
            events = self.extract_events(html, shop)
            if events:
                self.new_events.extend(events)
                print(f"  Found {len(events)} new event(s)")
            else:
                print(f"  No new events")
        else:
            print(f"  Could not fetch page")
    
    def run(self):
        """Main run"""
        print(f"📚 Comic Shop Event Scraper - {datetime.now().strftime('%Y-%m-%d')}")
        print(f"Checking {len(COMIC_SHOPS)} local comic shops...\n")
        
        for shop in COMIC_SHOPS:
            self.check_shop(shop)
        
        self.save_known_events()
        
        if self.new_events:
            print(f"\n✅ Found {len(self.new_events)} total new event(s)!")
            return self.format_message()
        else:
            print("\n✓ No new events found at any shops")
            return None
    
    def format_message(self):
        """Format Telegram message"""
        if not self.new_events:
            return None
        
        message = "📚 **Local Comic Shop Events!** 📚\n\n"
        
        # Group by shop
        by_shop = {}
        for event in self.new_events:
            shop = event['shop']
            if shop not in by_shop:
                by_shop[shop] = []
            by_shop[shop].append(event)
        
        for shop_name, events in by_shop.items():
            message += f"**{shop_name}**\n"
            message += f"📍 {events[0]['location']}\n"
            for event in events:
                message += f"• {event['title']}\n"
            message += f"🔗 [Website]({events[0]['url']})\n\n"
        
        message += "---\n"
        message += f"Scanned: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n"
        message += f"Shops checked: {len(COMIC_SHOPS)}"
        
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
    scraper = ComicShopScraper()
    message = scraper.run()
    
    if message:
        send_telegram(message)