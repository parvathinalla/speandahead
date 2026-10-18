"""Nearby merchant lookup and place-type normalization.

Coordinates are forwarded to Google Places for a one-time nearby search. They
are not persisted by CreditPilot. Keeping this integration on the server also
keeps the Places API key out of Flutter builds.
"""
from __future__ import annotations

from math import asin, cos, radians, sin, sqrt

import httpx


PLACE_CATEGORY_PRIORITY = (
    ("gas", {"gas_station", "electric_vehicle_charging_station"}),
    ("groceries", {"grocery_store", "supermarket", "convenience_store"}),
    ("dining", {
        "restaurant", "cafe", "coffee_shop", "bakery", "bar",
        "fast_food_restaurant", "meal_delivery", "meal_takeaway",
    }),
    ("transit", {
        "bus_station", "subway_station", "train_station", "transit_station",
        "parking", "taxi_stand",
    }),
    ("travel", {
        "airport", "hotel", "lodging", "car_rental", "travel_agency",
    }),
    ("entertainment", {"movie_theater"}),
    ("shopping", {"clothing_store", "department_store", "shopping_mall", "store"}),
)

# Nearby Search returns every kind of place when no type filter is supplied,
# including apartment complexes, landmarks, schools and offices. Restrict the
# provider request and validate its response again so only places where a card
# purchase is plausible reach the client.
PURCHASE_MERCHANT_TYPES = {
    "airport",
    "bakery",
    "bar",
    "cafe",
    "car_rental",
    "clothing_store",
    "coffee_shop",
    "convenience_store",
    "department_store",
    "electric_vehicle_charging_station",
    "gas_station",
    "grocery_store",
    "hotel",
    "movie_theater",
    "parking",
    "pharmacy",
    "restaurant",
    "shopping_mall",
    "store",
    "supermarket",
    "transit_station",
    "travel_agency",
}

NON_MERCHANT_TYPES = {
    "apartment_building",
    "apartment_complex",
    "condominium_complex",
    "corporate_office",
    "housing_complex",
    "landmark",
    "neighborhood",
    "plaza",
    "residential_building",
    "school",
}


def category_for_place(types: list[str] | tuple[str, ...]) -> str:
    normalized = {str(item).strip().lower() for item in types}
    for category, matches in PLACE_CATEGORY_PRIORITY:
        if normalized & matches:
            return category
    return "other"


def is_purchase_merchant(types: list[str] | tuple[str, ...], primary_type: str | None) -> bool:
    normalized = {str(item).strip().lower() for item in types}
    primary = str(primary_type or "").strip().lower()
    if primary in NON_MERCHANT_TYPES:
        return False
    return bool(normalized & PURCHASE_MERCHANT_TYPES or primary in PURCHASE_MERCHANT_TYPES)


def distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> int:
    """Return the great-circle distance between two coordinates."""
    earth_radius_m = 6_371_000
    phi1, phi2 = radians(lat1), radians(lat2)
    d_phi = radians(lat2 - lat1)
    d_lambda = radians(lng2 - lng1)
    value = sin(d_phi / 2) ** 2 + cos(phi1) * cos(phi2) * sin(d_lambda / 2) ** 2
    return round(earth_radius_m * 2 * asin(sqrt(value)))


async def nearby_merchants(
    latitude: float,
    longitude: float,
    api_key: str,
    radius_m: int = 250,
    limit: int = 8,
) -> list[dict]:
    payload = {
        "maxResultCount": limit,
        "rankPreference": "DISTANCE",
        "includedTypes": sorted(PURCHASE_MERCHANT_TYPES),
        "locationRestriction": {
            "circle": {
                "center": {"latitude": latitude, "longitude": longitude},
                "radius": float(radius_m),
            },
        },
    }
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": (
            "places.id,places.displayName,places.formattedAddress,"
            "places.primaryType,places.types,places.location,places.businessStatus"
        ),
    }
    async with httpx.AsyncClient(timeout=8) as client:
        response = await client.post(
            "https://places.googleapis.com/v1/places:searchNearby",
            headers=headers,
            json=payload,
        )
    response.raise_for_status()

    places = []
    for place in response.json().get("places", []):
        location = place.get("location", {})
        place_lat = location.get("latitude")
        place_lng = location.get("longitude")
        types = place.get("types", [])
        primary_type = place.get("primaryType")
        display_name = place.get("displayName", {})
        name = display_name.get("text") if isinstance(display_name, dict) else display_name
        place_id = place.get("id")
        if (not name or not place_id
                or place.get("businessStatus") not in (None, "OPERATIONAL")
                or not is_purchase_merchant(types, primary_type)):
            continue
        distance = None
        if place_lat is not None and place_lng is not None:
            distance = distance_meters(latitude, longitude, place_lat, place_lng)
        proximity_confidence = (
            "high" if distance is not None and distance <= 75 else
            "medium" if distance is not None and distance <= 300 else
            "low"
        )
        places.append({
            "place_id": place_id,
            "name": str(name)[:90],
            "address": str(place.get("formattedAddress", ""))[:180],
            "primary_type": primary_type,
            "category": category_for_place(types),
            "distance_m": distance,
            "proximity_confidence": proximity_confidence,
        })
    return places
