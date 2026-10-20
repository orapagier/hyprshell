"""Validate the dashboard's independently saved weather location."""
import math


def validate(data):
    if not isinstance(data, dict) or data.get('version') != 1:
        raise ValueError('Unsupported weather settings version')
    location = data.get('location')
    if location is not None:
        if not isinstance(location, dict) or not isinstance(location.get('name'), str) or not location['name'].strip() or len(location['name'].encode()) > 240:
            raise ValueError('Invalid weather location name')
        for key, limit in (('latitude', 90), ('longitude', 180)):
            value = location.get(key)
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or abs(value) > limit:
                raise ValueError('Invalid weather coordinates')
        location = {key: location[key] for key in ('name', 'latitude', 'longitude')}
    return {'version': 1, 'location': location}
