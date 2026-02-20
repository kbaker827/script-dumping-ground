#!/usr/bin/env python3
"""
Carolina Hurricanes NHL Schedule Monitor
Monitors for new games and sends Telegram alerts
"""

import json
import os
import sys
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
TEAM_NAME = "Carolina Hurricanes"
TEAM_ID = 12  # NHL API team ID
DATA_FILE = Path.home() / ".hurricanes_schedule.json"

# Telegram config
TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID', '')

class HurricanesMonitor:
    def __init__(self):
        self.known_games = self.load_known_games()
        self.new_games = []
    
    def load_known_games(self):
        """Load previously seen games"""
        if DATA_FILE.exists():
            try:
                with open(DATA_FILE, 'r') as f:
                    return json.load(f)
            except:
                return {}
        return {}
    
    def save_known_games(self):
        """Save seen games to disk"""
        with open(DATA_FILE, 'w') as f:
            json.dump(self.known_games, f, indent=2)
    
    def fetch_schedule(self):
        """Fetch schedule from NHL API"""
        try:
            # NHL API endpoint for team schedule
            url = f"https://api.nhle.com/stats/rest/en/team/{TEAM_ID}/schedule"
            
            # Alternative: Use the public schedule API
            today = datetime.now().strftime("%Y-%m-%d")
            end_date = (datetime.now() + timedelta(days=180)).strftime("%Y-%m-%d")
            
            url = f"https://statsapi.web.nhl.com/api/v1/schedule?teamId={TEAM_ID}&startDate={today}&endDate={end_date}"
            
            req = urllib.request.Request(
                url,
                headers={'User-Agent': 'Mozilla/5.0'}
            )
            
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.loads(response.read().decode('utf-8'))
                
        except Exception as e:
            print(f"Error fetching schedule: {e}")
            return None
    
    def check_games(self):
        """Check for new games"""
        schedule = self.fetch_schedule()
        if not schedule or 'dates' not in schedule:
            print("No schedule data available")
            return
        
        for date_info in schedule['dates']:
            date = date_info['date']
            for game in date_info['games']:
                game_id = str(game['gamePk'])
                
                # Skip if already known
                if game_id in self.known_games:
                    continue
                
                # Get game details
                home_team = game['teams']['home']['team']['name']
                away_team = game['teams']['away']['team']['name']
                venue = game.get('venue', {}).get('name', 'TBD')
                game_time = game.get('gameDate', 'TBD')
                
                # Determine if home or away
                is_home = home_team == TEAM_NAME
                opponent = away_team if is_home else home_team
                location = "Home" if is_home else "Away"
                
                game_info = {
                    'game_id': game_id,
                    'date': date,
                    'time': game_time,
                    'opponent': opponent,
                    'location': location,
                    'venue': venue,
                    'home_team': home_team,
                    'away_team': away_team
                }
                
                self.new_games.append(game_info)
                self.known_games[game_id] = game_info
                
                print(f"🏒 NEW GAME: {TEAM_NAME} vs {opponent} on {date}")
    
    def format_message(self):
        """Format Telegram message"""
        if not self.new_games:
            return None
        
        message = f"🏒 **{TEAM_NAME} Schedule Update!** 🏒\n\n"
        
        for game in self.new_games:
            opponent = game['opponent']
            date = game['date']
            location = game['location']
            venue = game['venue']
            
            # Format date nicely
            try:
                dt = datetime.strptime(date, "%Y-%m-%d")
                date_str = dt.strftime("%A, %B %d, %Y")
            except:
                date_str = date
            
            message += f"**vs {opponent}**\n"
            message += f"📅 {date_str}\n"
            message += f"🏟️ {location} - {venue}\n\n"
        
        message += "---\n"
        message += f"Checked: {datetime.now().strftime('%Y-%m-%d %H:%M')}"
        
        return message
    
    def run(self):
        """Main run"""
        print(f"🏒 Checking {TEAM_NAME} schedule...")
        self.check_games()
        
        if self.new_games:
            print(f"Found {len(self.new_games)} new game(s)!")
            message = self.format_message()
            self.save_known_games()
            return message
        else:
            print("No new games found")
            return None


def send_telegram(message):
    """Send Telegram message"""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        print("Telegram not configured")
        print(f"Message: {message}")
        return
    
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = {
            'chat_id': TELEGRAM_CHAT_ID,
            'text': message,
            'parse_mode': 'Markdown'
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
        print(f"Failed to send Telegram: {e}")


if __name__ == "__main__":
    monitor = HurricanesMonitor()
    message = monitor.run()
    
    if message:
        send_telegram(message)