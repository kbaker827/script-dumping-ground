#!/usr/bin/env python3
"""
Home Assistant Integration Script
Control smart home devices via Home Assistant API
"""

import os
import sys
import json
import urllib.request
import urllib.error
from pathlib import Path

# Default config - update these or set environment variables
DEFAULT_HA_URL = "https://dxqsmhi3owmqgg7bkx4df6kwg2x8ubmt.ui.nabu.casa"
DEFAULT_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiIzMjg0MDVkNjkxOGE0OTA4YWE1OTNkZWFkNWRhYTFkZCIsImlhdCI6MTc3MDA0Mjk5NCwiZXhwIjoyMDg1NDAyOTk0fQ.Ip9Rs-YtYoDDPGSzFIn812Wbc0YswltJ_j2CO2vsku0"

class HomeAssistantController:
    def __init__(self, url=None, token=None):
        self.url = url or os.environ.get('HA_URL') or DEFAULT_HA_URL
        self.token = token or os.environ.get('HA_TOKEN') or DEFAULT_TOKEN
        
        if not self.url or not self.token:
            raise ValueError("Home Assistant URL and token required")
    
    def _api_call(self, endpoint, method="GET", data=None):
        """Make API call to Home Assistant"""
        url = f"{self.url}/api/{endpoint}"
        
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json"
        }
        
        try:
            req = urllib.request.Request(
                url,
                headers=headers,
                method=method,
                data=json.dumps(data).encode() if data else None
            )
            
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.loads(response.read().decode())
                
        except urllib.error.HTTPError as e:
            print(f"API Error: {e.code} - {e.reason}")
            return None
        except Exception as e:
            print(f"Error: {e}")
            return None
    
    def get_status(self):
        """Get Home Assistant status"""
        return self._api_call("")
    
    def list_entities(self, domain=None):
        """List all entities or filter by domain (light, switch, climate, etc.)"""
        entities = self._api_call("states")
        if domain and entities:
            entities = [e for e in entities if e['entity_id'].startswith(f"{domain}.")]
        return entities
    
    def get_entity_state(self, entity_id):
        """Get state of specific entity"""
        return self._api_call(f"states/{entity_id}")
    
    def call_service(self, domain, service, entity_id=None, service_data=None):
        """Call a Home Assistant service"""
        data = service_data or {}
        if entity_id:
            data['entity_id'] = entity_id
        
        return self._api_call(
            f"services/{domain}/{service}",
            method="POST",
            data=data
        )
    
    # Light controls
    def light_on(self, entity_id, brightness=None, color=None):
        """Turn on a light"""
        data = {}
        if brightness:
            data['brightness'] = brightness  # 0-255
        if color:
            data['color_name'] = color
        return self.call_service("light", "turn_on", entity_id, data)
    
    def light_off(self, entity_id):
        """Turn off a light"""
        return self.call_service("light", "turn_off", entity_id)
    
    def light_toggle(self, entity_id):
        """Toggle a light"""
        return self.call_service("light", "toggle", entity_id)
    
    # Switch controls
    def switch_on(self, entity_id):
        return self.call_service("switch", "turn_on", entity_id)
    
    def switch_off(self, entity_id):
        return self.call_service("switch", "turn_off", entity_id)
    
    def switch_toggle(self, entity_id):
        return self.call_service("switch", "toggle", entity_id)
    
    # Climate controls
    def set_temperature(self, entity_id, temperature):
        """Set thermostat temperature"""
        return self.call_service("climate", "set_temperature", entity_id, {'temperature': temperature})
    
    def set_hvac_mode(self, entity_id, mode):
        """Set HVAC mode (off, heat, cool, auto)"""
        return self.call_service("climate", "set_hvac_mode", entity_id, {'hvac_mode': mode})
    
    # Lock controls
    def lock(self, entity_id):
        return self.call_service("lock", "lock", entity_id)
    
    def unlock(self, entity_id):
        return self.call_service("lock", "unlock", entity_id)
    
    # Scene activation
    def activate_scene(self, scene_id):
        return self.call_service("scene", "turn_on", scene_id)
    
    def show_dashboard(self):
        """Display quick status dashboard"""
        print("\n🏠 Home Assistant Dashboard")
        print("=" * 50)
        
        # Get lights
        lights = self.list_entities("light")
        if lights:
            print("\n💡 Lights:")
            for light in lights[:10]:  # Limit to 10
                state = "🟡" if light['state'] == 'on' else "⚫"
                friendly = light['attributes'].get('friendly_name', light['entity_id'])
                print(f"  {state} {friendly}")
        
        # Get climate
        climate = self.list_entities("climate")
        if climate:
            print("\n🌡️  Climate:")
            for c in climate:
                temp = c['attributes'].get('current_temperature', 'N/A')
                target = c['attributes'].get('temperature', 'N/A')
                mode = c['state']
                friendly = c['attributes'].get('friendly_name', c['entity_id'])
                print(f"  {friendly}: {temp}°F (Target: {target}°F, Mode: {mode})")
        
        # Get locks
        locks = self.list_entities("lock")
        if locks:
            print("\n🔒 Locks:")
            for lock in locks:
                state = "🔒" if lock['state'] == 'locked' else "🔓"
                friendly = lock['attributes'].get('friendly_name', lock['entity_id'])
                print(f"  {state} {friendly}")
        
        print("\n" + "=" * 50)


def main():
    """Main CLI interface"""
    if len(sys.argv) < 2:
        print("Usage:")
        print("  ha_control.py dashboard              - Show status dashboard")
        print("  ha_control.py lights                 - List all lights")
        print("  ha_control.py on <entity_id>         - Turn on light/switch")
        print("  ha_control.py off <entity_id>        - Turn off light/switch")
        print("  ha_control.py toggle <entity_id>     - Toggle light/switch")
        print("  ha_control.py temp <entity> <temp>   - Set thermostat")
        print("  ha_control.py lock <entity_id>       - Lock door")
        print("  ha_control.py unlock <entity_id>     - Unlock door")
        print("\nExamples:")
        print('  ha_control.py on light.living_room')
        print('  ha_control.py temp climate.thermostat 72')
        print('  ha_control.py lock lock.front_door')
        sys.exit(1)
    
    try:
        ha = HomeAssistantController()
        command = sys.argv[1].lower()
        
        if command == "dashboard":
            ha.show_dashboard()
        
        elif command == "lights":
            lights = ha.list_entities("light")
            print("\n💡 Available Lights:")
            for light in lights:
                print(f"  {light['entity_id']}")
        
        elif command == "on":
            entity_id = sys.argv[2]
            if entity_id.startswith("light."):
                ha.light_on(entity_id)
            else:
                ha.switch_on(entity_id)
            print(f"✅ Turned on {entity_id}")
        
        elif command == "off":
            entity_id = sys.argv[2]
            if entity_id.startswith("light."):
                ha.light_off(entity_id)
            else:
                ha.switch_off(entity_id)
            print(f"✅ Turned off {entity_id}")
        
        elif command == "toggle":
            entity_id = sys.argv[2]
            ha.light_toggle(entity_id)
            print(f"✅ Toggled {entity_id}")
        
        elif command == "temp":
            entity_id = sys.argv[2]
            temp = float(sys.argv[3])
            ha.set_temperature(entity_id, temp)
            print(f"✅ Set {entity_id} to {temp}°F")
        
        elif command == "lock":
            entity_id = sys.argv[2]
            ha.lock(entity_id)
            print(f"✅ Locked {entity_id}")
        
        elif command == "unlock":
            entity_id = sys.argv[2]
            ha.unlock(entity_id)
            print(f"✅ Unlocked {entity_id}")
        
        else:
            print(f"Unknown command: {command}")
            
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()