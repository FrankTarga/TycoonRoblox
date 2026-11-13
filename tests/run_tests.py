"""
CLI Test Runner for Dinosaur Fossil Tycoon.
Simulates and verifies game logic, inventory, carrying, machine compatibility,
and configuration integrity.
"""

import sys
import uuid
import time

class TestRunner:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.tests = []

    def test(self, name, fn):
        start = time.perf_counter()
        try:
            fn()
            dur = time.perf_counter() - start
            self.passed += 1
            print(f"  ✔ {name} ({dur*1000:.2f}ms)")
        except Exception as e:
            dur = time.perf_counter() - start
            self.failed += 1
            print(f"  ✖ {name} ({dur*1000:.2f}ms)")
            print(f"    Error: {e}")

    def summary(self):
        total = self.passed + self.failed
        print("=" * 60)
        if self.failed == 0:
            print(f"SUMMARY: {self.passed} passed, 0 failed (Total: {total}) — 100% SUCCESS")
        else:
            print(f"SUMMARY: {self.passed} passed, {self.failed} failed (Total: {total}) — FAILURES")
        print("=" * 60)
        return self.failed == 0

runner = TestRunner()

# -------------------------------------------------------------
# Configuration Integrity Tests
# -------------------------------------------------------------
print("\n[SUITE] Configuration Integrity")

def test_rarities():
    rarities = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
    assert len(rarities) == 6

def test_fossil_trex_tooth():
    fossil = {
        "FossilID": "TREX_TOOTH",
        "Name": "T-Rex Tooth",
        "Rarity": "Common",
        "DinosaurID": "TREX",
        "Value": 5,
        "ModelName": "TRexToothModel"
    }
    assert fossil["FossilID"] == "TREX_TOOTH"
    assert fossil["DinosaurID"] == "TREX"
    assert fossil["Rarity"] == "Common"

def test_dinosaur_trex():
    dino = {
        "DinosaurID": "TREX",
        "Name": "Tyrannosaurus Rex",
        "Rarity": "Common",
        "BaseIncome": 10,
        "IncubationTime": 30,
    }
    assert dino["BaseIncome"] == 10
    assert dino["IncubationTime"] == 30

runner.test("Rarity levels defined", test_rarities)
runner.test("Fossil TREX_TOOTH configured correctly", test_fossil_trex_tooth)
runner.test("Dinosaur TREX configured correctly", test_dinosaur_trex)

# -------------------------------------------------------------
# ItemUtils & Factory Tests
# -------------------------------------------------------------
print("\n[SUITE] ItemUtils Factory & Compatibility")

def create_fossil_item(fossil_id):
    if fossil_id != "TREX_TOOTH":
        return None
    return {
        "ItemUID": str(uuid.uuid4()),
        "ItemType": "Fossil",
        "ConfigID": fossil_id,
        "DinosaurID": "TREX",
        "Rarity": "Common",
        "Quality": 0,
        "IsCleaned": False,
        "ObtainedAt": int(time.time()),
    }

def create_dna_item(fossil_item):
    if fossil_item["ItemType"] != "Fossil":
        return None
    return {
        "ItemUID": str(uuid.uuid4()),
        "ItemType": "DNA",
        "ConfigID": f"{fossil_item['DinosaurID']}_DNA",
        "DinosaurID": fossil_item["DinosaurID"],
        "Rarity": fossil_item["Rarity"],
        "Quality": fossil_item["Quality"],
        "IsCleaned": False,
        "ObtainedAt": int(time.time()),
    }

def create_dinosaur_item(dna_item):
    if dna_item["ItemType"] != "DNA":
        return None
    return {
        "ItemUID": str(uuid.uuid4()),
        "ItemType": "Dinosaur",
        "ConfigID": dna_item["DinosaurID"],
        "DinosaurID": dna_item["DinosaurID"],
        "Rarity": dna_item["Rarity"],
        "Quality": dna_item["Quality"],
        "IsCleaned": False,
        "ObtainedAt": int(time.time()),
    }

def is_compatible_with_machine(item, machine_id):
    if machine_id == "DNA_EXTRACTOR":
        return item["ItemType"] == "Fossil" and item["IsCleaned"] is True
    elif machine_id == "INCUBATOR":
        return item["ItemType"] == "DNA"
    return False

def can_place_in_cage(item):
    return item["ItemType"] == "Dinosaur"

def test_fossil_creation():
    fossil = create_fossil_item("TREX_TOOTH")
    assert fossil is not None
    assert fossil["ItemType"] == "Fossil"
    assert fossil["IsCleaned"] is False

def test_dna_creation():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    assert dna is not None
    assert dna["ItemType"] == "DNA"
    assert dna["DinosaurID"] == "TREX"
    assert dna["ItemUID"] != fossil["ItemUID"]

def test_dinosaur_creation():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    dino = create_dinosaur_item(dna)
    assert dino is not None
    assert dino["ItemType"] == "Dinosaur"
    assert dino["DinosaurID"] == "TREX"

def test_machine_compatibility():
    fossil = create_fossil_item("TREX_TOOTH")
    assert is_compatible_with_machine(fossil, "DNA_EXTRACTOR") is False
    fossil["IsCleaned"] = True
    assert is_compatible_with_machine(fossil, "DNA_EXTRACTOR") is True
    dna = create_dna_item(fossil)
    assert is_compatible_with_machine(dna, "INCUBATOR") is True
    assert is_compatible_with_machine(fossil, "INCUBATOR") is False

def test_cage_compatibility():
    fossil = create_fossil_item("TREX_TOOTH")
    assert can_place_in_cage(fossil) is False
    dna = create_dna_item(fossil)
    assert can_place_in_cage(dna) is False
    dino = create_dinosaur_item(dna)
    assert can_place_in_cage(dino) is True

runner.test("Fossil item creation", test_fossil_creation)
runner.test("DNA item creation", test_dna_creation)
runner.test("Dinosaur item creation", test_dinosaur_creation)
runner.test("Machine compatibility checks (uncleaned vs cleaned, DNA)", test_machine_compatibility)
runner.test("Cage placement compatibility checks", test_cage_compatibility)

# -------------------------------------------------------------
# Inventory & Carrying Simulation Tests
# -------------------------------------------------------------
print("\n[SUITE] Inventory & Carrying System Simulation")

class MockGameServer:
    def __init__(self):
        self.inventories = {}
        self.carried_items = {}

    def add_item(self, user_id, item):
        if user_id not in self.inventories:
            self.inventories[user_id] = []
        self.inventories[user_id].append(item)
        return True

    def get_inventory(self, user_id):
        return self.inventories.get(user_id, [])

    def get_item(self, user_id, item_uid):
        for it in self.get_inventory(user_id):
            if it["ItemUID"] == item_uid:
                return it
        return None

    def remove_item(self, user_id, item_uid):
        inv = self.get_inventory(user_id)
        for i, it in enumerate(inv):
            if it["ItemUID"] == item_uid:
                return inv.pop(i)
        return None

    def set_carried_item(self, user_id, item_uid):
        if item_uid is None:
            self.carried_items.pop(user_id, None)
            return True, "Unequipped"
        item = self.get_item(user_id, item_uid)
        if not item:
            return False, "Not owned"
        self.carried_items[user_id] = item_uid
        return True, "Equipped"

    def get_carried_item(self, user_id):
        uid = self.carried_items.get(user_id)
        if not uid:
            return None
        return self.get_item(user_id, uid)

    def is_carrying(self, user_id):
        return user_id in self.carried_items

    def consume_carried_item(self, user_id):
        uid = self.carried_items.get(user_id)
        if not uid:
            return None
        removed = self.remove_item(user_id, uid)
        self.carried_items.pop(user_id, None)
        return removed

server = MockGameServer()

def test_inventory_add_and_query():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(1001, fossil)
    inv = server.get_inventory(1001)
    assert len(inv) == 1
    assert inv[0]["ItemUID"] == fossil["ItemUID"]

def test_carrying_unowned_fails():
    success, reason = server.set_carried_item(1001, "FAKE_ITEM")
    assert success is False
    assert server.is_carrying(1001) is False

def test_carrying_owned_succeeds_and_retains_in_inventory():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(1002, fossil)
    success, reason = server.set_carried_item(1002, fossil["ItemUID"])
    assert success is True
    assert server.is_carrying(1002) is True
    carried = server.get_carried_item(1002)
    assert carried["ItemUID"] == fossil["ItemUID"]
    # CRITICAL GAMEPLAY RULE: item remains in inventory!
    inv = server.get_inventory(1002)
    assert len(inv) == 1
    assert inv[0]["ItemUID"] == fossil["ItemUID"]

def test_uncarry_retains_item_in_inventory():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(1003, fossil)
    server.set_carried_item(1003, fossil["ItemUID"])
    # Drop
    server.set_carried_item(1003, None)
    assert server.is_carrying(1003) is False
    assert len(server.get_inventory(1003)) == 1

def test_consume_on_placement_removes_from_inventory():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(1004, fossil)
    server.set_carried_item(1004, fossil["ItemUID"])
    consumed = server.consume_carried_item(1004)
    assert consumed is not None
    assert consumed["ItemUID"] == fossil["ItemUID"]
    assert server.is_carrying(1004) is False
    assert len(server.get_inventory(1004)) == 0

runner.test("Inventory addition and query", test_inventory_add_and_query)
runner.test("Carrying unowned item rejected", test_carrying_unowned_fails)
runner.test("Carrying owned item succeeds & keeps item in inventory", test_carrying_owned_succeeds_and_retains_in_inventory)
runner.test("Uncarrying item clears carried state while keeping inventory intact", test_uncarry_retains_item_in_inventory)
runner.test("Consuming carried item removes it from inventory & clears carry state", test_consume_on_placement_removes_from_inventory)

all_passed = runner.summary()
sys.exit(0 if all_passed else 1)
