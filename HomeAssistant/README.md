# Home Assistant Control Script

Command-line interface for controlling Home Assistant smart home devices.

## Features

- Control lights (on/off/toggle, brightness, color)
- Control switches
- Adjust thermostat
- Lock/unlock doors
- Activate scenes
- View dashboard status

## Setup

The script uses your Home Assistant URL and token from `TOOLS.md` by default, or you can set environment variables:

```bash
export HA_URL="https://your-ha-instance.ui.nabu.casa"
export HA_TOKEN="your_long_lived_access_token"
```

## Usage

### Show Dashboard
```bash
python3 ha_control.py dashboard
```

### Control Lights
```bash
# Turn on
python3 ha_control.py on light.kitchen

# Turn off
python3 ha_control.py off light.living_room

# Toggle
python3 ha_control.py toggle light.bedroom
```

### Control Switches
```bash
python3 ha_control.py on switch.fireplace_socket_1
python3 ha_control.py off switch.bat_signal_socket_1
```

### Adjust Thermostat
```bash
python3 ha_control.py temp climate.dining_room_thermostat 72
```

### Control Locks
```bash
python3 ha_control.py lock lock.front_door
python3 ha_control.py unlock lock.front_door
```

### List All Lights
```bash
python3 ha_control.py lights
```

## Available Entities (from your setup)

**Lights:**
- `light.kitchen`
- `light.living_room_fan_light`
- `light.living_room_lamp_1`
- `light.living_room_lamp_2`
- `light.master_bedroom_fan`
- `light.master_bathroom_all`
- `light.office_1`, `light.office_2`, `light.office_3`
- `light.front_porch`
- `light.foyer`
- `light.pool_rope_lights`
- `light.kyles_lamp`, `light.amandas_lamp`

**Climate:**
- `climate.dining_room_thermostat`
- `climate.fireplace_remote_sh3002`

**Locks:**
- `lock.front_door`

**Switches:**
- `switch.fireplace_socket_1`
- `switch.bat_signal_socket_1`
- `switch.dishwasher`

## Automation Ideas

```bash
# Turn on lights at sunset (add to cron)
python3 ha_control.py on light.front_porch
python3 ha_control.py on light.foyer

# Goodnight routine
python3 ha_control.py off light.kitchen
python3 ha_control.py off light.living_room_fan_light
python3 ha_control.py lock lock.front_door
python3 ha_control.py temp climate.dining_room_thermostat 68
```

## Requirements

- Python 3.6+
- Home Assistant instance with API enabled
- Long-lived access token
