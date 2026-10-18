from location_service import category_for_place, distance_meters, is_purchase_merchant


def test_place_types_map_to_card_reward_categories():
    assert category_for_place(["store", "grocery_store"]) == "groceries"
    assert category_for_place(["coffee_shop", "food"]) == "dining"
    assert category_for_place(["airport"]) == "travel"
    assert category_for_place(["clothing_store"]) == "shopping"
    assert category_for_place(["movie_theater"]) == "entertainment"


def test_distance_is_zero_for_same_coordinate():
    assert distance_meters(40.7, -74.0, 40.7, -74.0) == 0


def test_residential_and_noncommercial_places_are_not_merchants():
    assert not is_purchase_merchant(
        ["apartment_complex", "point_of_interest"], "apartment_complex")
    assert not is_purchase_merchant(["plaza", "landmark"], "plaza")
    assert not is_purchase_merchant(["corporate_office"], "corporate_office")


def test_real_purchase_locations_are_merchants():
    assert is_purchase_merchant(["grocery_store", "store"], "grocery_store")
    assert is_purchase_merchant(["coffee_shop", "food"], "coffee_shop")
    assert is_purchase_merchant(["hotel", "lodging"], "hotel")
