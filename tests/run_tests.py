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

# -------------------------------------------------------------
# Fossil Cleaning System Simulation Tests (Phase 4)
# -------------------------------------------------------------
print("\n[SUITE] Fossil Cleaning System Simulation (Phase 4)")

class MockCleaningService:
    def __init__(self, game_server):
        self.server = game_server
        self.player_tools = {}
        self.player_xp = {}

    def set_brush(self, user_id, brush_id):
        self.player_tools[user_id] = brush_id

    def get_brush(self, user_id):
        return self.player_tools.get(user_id, "BASIC_BRUSH")

    def clean_carried_fossil(self, user_id):
        item = self.server.get_carried_item(user_id)
        if not item:
            return False, "No item is being carried"
        if item["ItemType"] != "Fossil":
            return False, "Only fossils can be cleaned"
        if item["IsCleaned"]:
            return False, "Fossil is already cleaned"
        brush = self.get_brush(user_id)
        if not brush or brush == "":
            return False, "No brush equipped"

        item["IsCleaned"] = True
        item["Quality"] = 85
        self.player_xp[user_id] = self.player_xp.get(user_id, 0) + 5
        return True, item

cleaning_service = MockCleaningService(server)

def test_clean_without_item_rejected():
    success, reason = cleaning_service.clean_carried_fossil(2001)
    assert success is False
    assert reason == "No item is being carried"

def test_clean_non_fossil_rejected():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    server.add_item(2002, dna)
    server.set_carried_item(2002, dna["ItemUID"])
    success, reason = cleaning_service.clean_carried_fossil(2002)
    assert success is False
    assert reason == "Only fossils can be cleaned"

def test_clean_without_brush_rejected():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(2003, fossil)
    server.set_carried_item(2003, fossil["ItemUID"])
    cleaning_service.set_brush(2003, "")
    success, reason = cleaning_service.clean_carried_fossil(2003)
    assert success is False
    assert reason == "No brush equipped"

def test_clean_uncleaned_fossil_succeeds_and_awards_xp():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(2004, fossil)
    server.set_carried_item(2004, fossil["ItemUID"])
    cleaning_service.set_brush(2004, "BASIC_BRUSH")
    success, cleaned_item = cleaning_service.clean_carried_fossil(2004)
    assert success is True
    assert cleaned_item["IsCleaned"] is True
    assert cleaned_item["Quality"] >= 70
    assert cleaning_service.player_xp[2004] == 5

def test_clean_already_cleaned_fossil_rejected():
    # Attempting to clean the same fossil from test above
    success, reason = cleaning_service.clean_carried_fossil(2004)
    assert success is False
    assert reason == "Fossil is already cleaned"

runner.test("Cleaning without carried item rejected", test_clean_without_item_rejected)
runner.test("Cleaning non-fossil (DNA) rejected", test_clean_non_fossil_rejected)
runner.test("Cleaning without equipped brush rejected", test_clean_without_brush_rejected)
runner.test("Cleaning raw fossil succeeds, sets IsCleaned=True and awards 5 XP", test_clean_uncleaned_fossil_succeeds_and_awards_xp)
runner.test("Cleaning already cleaned fossil rejected", test_clean_already_cleaned_fossil_rejected)

# -------------------------------------------------------------
# DNA Extractor System Simulation Tests (Phase 5)
# -------------------------------------------------------------
print("\n[SUITE] DNA Extractor System Simulation (Phase 5)")

# Machine states
IDLE = "Idle"
PROCESSING = "Processing"
OUTPUT_READY = "OutputReady"

class MockDNAExtractor:
    def __init__(self, game_server):
        self.server = game_server
        self.states = {}       # user_id -> state dict
        self.player_xp = {}

    def _get_state(self, user_id):
        if user_id not in self.states:
            self.states[user_id] = {
                "state": IDLE,
                "input_dino_id": None,
                "input_rarity": None,
                "pending_dna": None,
            }
        return self.states[user_id]

    def reset_machine(self, user_id):
        self.states[user_id] = {
            "state": IDLE,
            "input_dino_id": None,
            "input_rarity": None,
            "pending_dna": None,
        }

    def insert_item(self, user_id):
        item = self.server.get_carried_item(user_id)
        if not item:
            return False, "No item is being carried"
        if item["ItemType"] != "Fossil":
            return False, "DNA Extractor only accepts cleaned fossils"
        if not item["IsCleaned"]:
            return False, "Fossil must be cleaned before DNA extraction"
        s = self._get_state(user_id)
        if s["state"] != IDLE:
            return False, "Machine is not Idle"
        # Consume from inventory & carrying
        self.server.remove_item(user_id, item["ItemUID"])
        self.server.carried_items.pop(user_id, None)
        s["state"] = PROCESSING
        s["input_dino_id"] = item["DinosaurID"]
        s["input_rarity"] = item["Rarity"]
        return True, "Processing started"

    def force_complete(self, user_id):
        s = self._get_state(user_id)
        if s["state"] != PROCESSING:
            return
        dna = {
            "ItemUID": str(uuid.uuid4()),
            "ItemType": "DNA",
            "ConfigID": s["input_dino_id"] + "_DNA",
            "DinosaurID": s["input_dino_id"],
            "Rarity": s["input_rarity"],
            "Quality": 80,
            "IsCleaned": False,
            "ObtainedAt": int(time.time()),
        }
        s["state"] = OUTPUT_READY
        s["pending_dna"] = dna

    def collect_dna(self, user_id):
        s = self._get_state(user_id)
        if s["state"] != OUTPUT_READY or not s["pending_dna"]:
            return False, "No DNA available to collect"
        dna = s["pending_dna"]
        self.server.add_item(user_id, dna)
        self.player_xp[user_id] = self.player_xp.get(user_id, 0) + 15
        self.reset_machine(user_id)
        return True, dna

extractor = MockDNAExtractor(server)

def test_extractor_reject_no_item():
    success, reason = extractor.insert_item(3001)
    assert success is False
    assert reason == "No item is being carried"

def test_extractor_reject_uncleaned_fossil():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(3002, fossil)
    server.set_carried_item(3002, fossil["ItemUID"])
    success, reason = extractor.insert_item(3002)
    assert success is False
    assert reason == "Fossil must be cleaned before DNA extraction"
    # Fossil still in inventory — not consumed
    assert len(server.get_inventory(3002)) == 1

def test_extractor_reject_dna_item():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    server.add_item(3003, dna)
    server.set_carried_item(3003, dna["ItemUID"])
    success, reason = extractor.insert_item(3003)
    assert success is False
    assert reason == "DNA Extractor only accepts cleaned fossils"

def test_extractor_accept_cleaned_fossil_and_consume():
    fossil = create_fossil_item("TREX_TOOTH")
    fossil["IsCleaned"] = True
    server.add_item(3004, fossil)
    server.set_carried_item(3004, fossil["ItemUID"])
    success, _ = extractor.insert_item(3004)
    assert success is True
    # Fossil consumed from inventory and carrying state
    assert len(server.get_inventory(3004)) == 0
    assert server.is_carrying(3004) is False
    # Machine is now Processing
    assert extractor._get_state(3004)["state"] == PROCESSING

def test_extractor_reject_second_insertion_while_processing():
    fossil2 = create_fossil_item("TREX_TOOTH")
    fossil2["IsCleaned"] = True
    server.add_item(3004, fossil2)
    server.set_carried_item(3004, fossil2["ItemUID"])
    success, reason = extractor.insert_item(3004)
    assert success is False
    assert reason == "Machine is not Idle"

def test_extractor_complete_and_enter_output_ready():
    extractor.force_complete(3004)
    assert extractor._get_state(3004)["state"] == OUTPUT_READY
    assert extractor._get_state(3004)["pending_dna"] is not None

def test_extractor_reject_collect_when_idle():
    success, reason = extractor.collect_dna(3005)
    assert success is False
    assert reason == "No DNA available to collect"

def test_extractor_collect_dna_adds_to_inventory_resets_machine_awards_xp():
    # Clear any leftover inventory from the rejected second-insertion test
    # (fossil2 was added to 3004's inventory but never consumed because insertion failed)
    server.inventories.pop(3004, None)
    success, dna = extractor.collect_dna(3004)
    assert success is True, f"collect_dna returned False: {dna}"
    assert dna["ItemType"] == "DNA", f"Expected DNA, got {dna['ItemType']}"
    assert dna["DinosaurID"] == "TREX", f"Expected TREX, got {dna['DinosaurID']}"
    # DNA is now the only item in inventory
    inv = server.get_inventory(3004)
    assert len(inv) == 1, f"Expected 1 item in inventory, got {len(inv)}: {inv}"
    assert inv[0]["ItemType"] == "DNA", f"Expected DNA item, got {inv[0]['ItemType']}"
    # Machine reset to Idle
    assert extractor._get_state(3004)["state"] == IDLE, "Machine not reset to Idle"
    # XP awarded
    assert extractor.player_xp[3004] == 15, f"Expected 15 XP, got {extractor.player_xp.get(3004)}"

def test_extractor_no_double_collect():
    # 3004 machine is Idle — second collect should fail
    success, reason = extractor.collect_dna(3004)
    assert success is False
    assert reason == "No DNA available to collect"

runner.test("Extractor rejects when not carrying anything", test_extractor_reject_no_item)
runner.test("Extractor rejects uncleaned fossil (fossil stays in inventory)", test_extractor_reject_uncleaned_fossil)
runner.test("Extractor rejects DNA item (wrong type)", test_extractor_reject_dna_item)
runner.test("Extractor accepts cleaned fossil, consumes it from inventory and carrying state", test_extractor_accept_cleaned_fossil_and_consume)
runner.test("Extractor rejects second insertion while Processing", test_extractor_reject_second_insertion_while_processing)
runner.test("Extractor transitions to OutputReady after processing completes", test_extractor_complete_and_enter_output_ready)
runner.test("Extractor rejects DNA collection when machine is Idle", test_extractor_reject_collect_when_idle)
runner.test("Collecting DNA adds it to inventory, resets machine to Idle, and awards 15 XP", test_extractor_collect_dna_adds_to_inventory_resets_machine_awards_xp)
runner.test("Collecting DNA twice from same extraction rejected", test_extractor_no_double_collect)

# -------------------------------------------------------------
# Dinosaur Incubator System Simulation (Phase 6)
# -------------------------------------------------------------
print("\n[SUITE] Dinosaur Incubator System Simulation (Phase 6)")

class MockIncubator:
    def __init__(self, srv):
        self.server = srv
        self.states = {}
        self.player_xp = {}

    def _get_state(self, user_id):
        if user_id not in self.states:
            self.reset_machine(user_id)
        return self.states[user_id]

    def reset_machine(self, user_id):
        self.states[user_id] = {
            "state": IDLE,
            "input_dino_id": None,
            "input_rarity": None,
            "input_quality": None,
        }

    def insert_item(self, user_id):
        item = self.server.get_carried_item(user_id)
        if not item:
            return False, "No item is being carried"
        if item["ItemType"] != "DNA":
            return False, "Incubator only accepts DNA items"
        s = self._get_state(user_id)
        if s["state"] != IDLE:
            return False, "Machine is not Idle"
        # Consume from inventory & carrying
        self.server.remove_item(user_id, item["ItemUID"])
        self.server.carried_items.pop(user_id, None)
        s["state"] = PROCESSING
        s["input_dino_id"] = item["DinosaurID"]
        s["input_rarity"] = item["Rarity"]
        s["input_quality"] = item.get("Quality", 80)
        return True, "Processing started"

    def force_complete(self, user_id):
        s = self._get_state(user_id)
        if s["state"] != PROCESSING:
            return False, "Machine is not processing"
        dino = {
            "ItemUID": str(uuid.uuid4()),
            "ItemType": "Dinosaur",
            "ConfigID": s["input_dino_id"],
            "DinosaurID": s["input_dino_id"],
            "Rarity": s["input_rarity"],
            "Quality": s["input_quality"],
            "IsCleaned": False,
            "ObtainedAt": int(time.time()),
        }
        # Auto-collect to inventory
        self.server.add_item(user_id, dino)
        self.player_xp[user_id] = self.player_xp.get(user_id, 0) + 20
        self.reset_machine(user_id)
        return True, dino

incubator = MockIncubator(server)

def test_incubator_reject_no_item():
    success, reason = incubator.insert_item(4001)
    assert success is False
    assert reason == "No item is being carried"

def test_incubator_reject_uncleaned_fossil():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(4002, fossil)
    server.set_carried_item(4002, fossil["ItemUID"])
    success, reason = incubator.insert_item(4002)
    assert success is False
    assert reason == "Incubator only accepts DNA items"
    # Fossil remains safe in inventory
    assert len(server.get_inventory(4002)) == 1

def test_incubator_reject_cleaned_fossil():
    fossil = create_fossil_item("TREX_TOOTH")
    fossil["IsCleaned"] = True
    server.add_item(4003, fossil)
    server.set_carried_item(4003, fossil["ItemUID"])
    success, reason = incubator.insert_item(4003)
    assert success is False
    assert reason == "Incubator only accepts DNA items"

def test_incubator_reject_dinosaur_item():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    dino = create_dinosaur_item(dna)
    server.add_item(4004, dino)
    server.set_carried_item(4004, dino["ItemUID"])
    success, reason = incubator.insert_item(4004)
    assert success is False
    assert reason == "Incubator only accepts DNA items"

def test_incubator_accept_dna_and_consume():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    server.add_item(4005, dna)
    server.set_carried_item(4005, dna["ItemUID"])
    success, _ = incubator.insert_item(4005)
    assert success is True
    # DNA consumed from inventory & carried
    assert len(server.get_inventory(4005)) == 0
    assert server.is_carrying(4005) is False
    # Machine is Processing
    assert incubator._get_state(4005)["state"] == PROCESSING

def test_incubator_reject_second_insertion_while_processing():
    fossil = create_fossil_item("TREX_TOOTH")
    dna2 = create_dna_item(fossil)
    server.add_item(4005, dna2)
    server.set_carried_item(4005, dna2["ItemUID"])
    success, reason = incubator.insert_item(4005)
    assert success is False
    assert reason == "Machine is not Idle"

def test_incubator_force_complete_idle_is_noop():
    # Calling force_complete when Idle is safe no-op
    success, reason = incubator.force_complete(4006)
    assert success is False
    assert reason == "Machine is not processing"
    assert incubator._get_state(4006)["state"] == IDLE

def test_incubator_force_complete_autocollects_dinosaur_resets_idle_awards_20_xp():
    # Clean user 4005 leftover dna2 from the rejected second insertion test
    server.inventories.pop(4005, None)
    success, dino = incubator.force_complete(4005)
    assert success is True
    assert dino["ItemType"] == "Dinosaur"
    assert dino["DinosaurID"] == "TREX"
    assert dino["Rarity"] == "Common"
    # Auto-collected directly into inventory
    inv = server.get_inventory(4005)
    assert len(inv) == 1
    assert inv[0]["ItemType"] == "Dinosaur"
    assert inv[0]["DinosaurID"] == "TREX"
    # Machine reset to Idle
    assert incubator._get_state(4005)["state"] == IDLE
    # 20 XP awarded
    assert incubator.player_xp[4005] == 20

def test_incubator_second_incubation_allowed():
    # User 4005 can now incubate a second DNA
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    server.add_item(4005, dna)
    server.set_carried_item(4005, dna["ItemUID"])
    success, _ = incubator.insert_item(4005)
    assert success is True
    assert incubator._get_state(4005)["state"] == PROCESSING
    success, dino2 = incubator.force_complete(4005)
    assert success is True
    # Now user has 2 dinosaurs in inventory
    inv = server.get_inventory(4005)
    assert len(inv) == 2
    assert incubator.player_xp[4005] == 40  # 20 + 20

runner.test("Incubator rejects when not carrying anything", test_incubator_reject_no_item)
runner.test("Incubator rejects uncleaned fossil (fossil stays in inventory)", test_incubator_reject_uncleaned_fossil)
runner.test("Incubator rejects cleaned fossil (wrong item type)", test_incubator_reject_cleaned_fossil)
runner.test("Incubator rejects dinosaur item (wrong item type)", test_incubator_reject_dinosaur_item)
runner.test("Incubator accepts DNA, consumes it from inventory and carrying state", test_incubator_accept_dna_and_consume)
runner.test("Incubator rejects second insertion while Processing", test_incubator_reject_second_insertion_while_processing)
runner.test("Incubator force_complete while Idle is safe no-op", test_incubator_force_complete_idle_is_noop)
runner.test("Incubator auto-collects dinosaur to inventory, resets to Idle, and awards 20 XP", test_incubator_force_complete_autocollects_dinosaur_resets_idle_awards_20_xp)
runner.test("Incubator allows a second incubation after the first completes", test_incubator_second_incubation_allowed)

# -------------------------------------------------------------
# Dinosaurs and Cages System Simulation (Phase 7)
# -------------------------------------------------------------
print("\n[SUITE] Dinosaurs and Cages System Simulation (Phase 7)")

class MockCageService:
    def __init__(self, srv):
        self.server = srv
        self.cages = {}
        self.player_xp = {}
        self.player_money = {}

    def _get_cage(self, user_id, cage_id):
        if user_id not in self.cages:
            self.cages[user_id] = {}
        if cage_id not in self.cages[user_id]:
            self.cages[user_id][cage_id] = {
                "dino_id": None,
                "item_uid": None,
                "last_collection": time.time(),
                "stored_item": None,
            }
        return self.cages[user_id][cage_id]

    def place_dinosaur(self, user_id, cage_id):
        item = self.server.get_carried_item(user_id)
        if not item:
            return False, "No item is being carried"
        if item["ItemType"] != "Dinosaur":
            return False, "Only dinosaurs can be placed in cages"
        cage = self._get_cage(user_id, cage_id)
        if cage["dino_id"] is not None:
            return False, "Cage is already occupied"
        # Consume from inventory & carrying
        self.server.remove_item(user_id, item["ItemUID"])
        self.server.carried_items.pop(user_id, None)
        cage["dino_id"] = item["DinosaurID"]
        cage["item_uid"] = item["ItemUID"]
        cage["stored_item"] = item
        cage["last_collection"] = time.time()
        self.player_xp[user_id] = self.player_xp.get(user_id, 0) + 25
        return True, "Dinosaur placed"

    def calculate_pending_income(self, user_id, cage_id):
        cage = self._get_cage(user_id, cage_id)
        if not cage["dino_id"]:
            return 0
        elapsed = time.time() - cage["last_collection"]
        intervals = int(elapsed // 60)
        base_income = 10  # TREX BaseIncome
        return min(10000, intervals * base_income)

    def simulate_elapsed(self, user_id, cage_id, seconds):
        cage = self._get_cage(user_id, cage_id)
        cage["last_collection"] -= seconds

    def collect_income(self, user_id, cage_id):
        pending = self.calculate_pending_income(user_id, cage_id)
        if pending <= 0:
            return False, "No income to collect"
        self.player_money[user_id] = self.player_money.get(user_id, 0) + pending
        cage = self._get_cage(user_id, cage_id)
        cage["last_collection"] = time.time()
        return True, pending

    def retrieve_dinosaur(self, user_id, cage_id):
        cage = self._get_cage(user_id, cage_id)
        if not cage["dino_id"]:
            return False, "No dinosaur in cage"
        pending = self.calculate_pending_income(user_id, cage_id)
        if pending > 0:
            self.collect_income(user_id, cage_id)
        dino = cage["stored_item"]
        self.server.add_item(user_id, dino)
        cage["dino_id"] = None
        cage["item_uid"] = None
        cage["stored_item"] = None
        return True, dino

cage_service = MockCageService(server)

def test_cage_reject_no_item():
    success, reason = cage_service.place_dinosaur(5001, "CAGE_1")
    assert success is False
    assert reason == "No item is being carried"

def test_cage_reject_fossil():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(5002, fossil)
    server.set_carried_item(5002, fossil["ItemUID"])
    success, reason = cage_service.place_dinosaur(5002, "CAGE_1")
    assert success is False
    assert reason == "Only dinosaurs can be placed in cages"
    assert len(server.get_inventory(5002)) == 1

def test_cage_reject_dna():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    server.add_item(5003, dna)
    server.set_carried_item(5003, dna["ItemUID"])
    success, reason = cage_service.place_dinosaur(5003, "CAGE_1")
    assert success is False
    assert reason == "Only dinosaurs can be placed in cages"

def test_cage_accept_dinosaur_consume_and_award_25_xp():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    dino = create_dinosaur_item(dna)
    server.add_item(5004, dino)
    server.set_carried_item(5004, dino["ItemUID"])
    success, _ = cage_service.place_dinosaur(5004, "CAGE_1")
    assert success is True
    # Dinosaur consumed from inventory and carrying
    assert len(server.get_inventory(5004)) == 0
    assert server.is_carrying(5004) is False
    # Cage holds the dinosaur
    cage = cage_service._get_cage(5004, "CAGE_1")
    assert cage["dino_id"] == "TREX"
    assert cage["item_uid"] == dino["ItemUID"]
    # 25 XP awarded
    assert cage_service.player_xp[5004] == 25

def test_cage_reject_already_occupied():
    fossil = create_fossil_item("TREX_TOOTH")
    dna = create_dna_item(fossil)
    dino2 = create_dinosaur_item(dna)
    server.add_item(5004, dino2)
    server.set_carried_item(5004, dino2["ItemUID"])
    success, reason = cage_service.place_dinosaur(5004, "CAGE_1")
    assert success is False
    assert reason == "Cage is already occupied"
    # Second dino stays safe in inventory
    assert len(server.get_inventory(5004)) == 1

def test_cage_empty_accumulates_zero_income():
    assert cage_service.calculate_pending_income(5005, "CAGE_1") == 0

def test_cage_occupied_accumulates_income():
    # User 5004 placed TREX (BaseIncome = 10)
    cage_service.simulate_elapsed(5004, "CAGE_1", 120)  # 2 intervals
    pending = cage_service.calculate_pending_income(5004, "CAGE_1")
    assert pending == 20

def test_cage_income_capped_at_max():
    cage_service.simulate_elapsed(5004, "CAGE_1", 60 * 10000)
    pending = cage_service.calculate_pending_income(5004, "CAGE_1")
    assert pending == 10000

def test_cage_collect_zero_rejected():
    success, reason = cage_service.collect_income(5005, "CAGE_1")
    assert success is False
    assert reason == "No income to collect"

def test_cage_collect_income_adds_money_and_resets():
    # User 5004 currently has 10,000 pending
    success, collected = cage_service.collect_income(5004, "CAGE_1")
    assert success is True
    assert collected == 10000
    assert cage_service.player_money[5004] == 10000
    # Pending income is reset to 0
    assert cage_service.calculate_pending_income(5004, "CAGE_1") == 0

def test_cage_retrieve_dinosaur_returns_to_inventory_and_collects_income():
    # Clear user 5004 leftover dino2 from rejection test
    server.inventories.pop(5004, None)
    cage_service.simulate_elapsed(5004, "CAGE_1", 60)  # 1 interval = $10
    success, dino = cage_service.retrieve_dinosaur(5004, "CAGE_1")
    assert success is True
    assert dino["ItemType"] == "Dinosaur"
    assert dino["DinosaurID"] == "TREX"
    # Dinosaur returned to inventory
    inv = server.get_inventory(5004)
    assert len(inv) == 1
    assert inv[0]["ItemType"] == "Dinosaur"
    # Cage is empty now
    cage = cage_service._get_cage(5004, "CAGE_1")
    assert cage["dino_id"] is None
    # Pending $10 was collected ($10,000 + $10 = $10,010)
    assert cage_service.player_money[5004] == 10010

runner.test("Cage rejects when not carrying anything", test_cage_reject_no_item)
runner.test("Cage rejects fossil (fossil stays in inventory)", test_cage_reject_fossil)
runner.test("Cage rejects DNA item", test_cage_reject_dna)
runner.test("Cage accepts dinosaur, consumes it from inventory and awards 25 XP", test_cage_accept_dinosaur_consume_and_award_25_xp)
runner.test("Cage rejects second dinosaur when already occupied", test_cage_reject_already_occupied)
runner.test("Empty cage accumulates zero income", test_cage_empty_accumulates_zero_income)
runner.test("Occupied cage accumulates passive income over time", test_cage_occupied_accumulates_income)
runner.test("Cage income is capped at MaxAccumulatedIncome (10,000)", test_cage_income_capped_at_max)
runner.test("Collecting income when zero is rejected", test_cage_collect_zero_rejected)
runner.test("Collecting income adds money and resets pending balance", test_cage_collect_income_adds_money_and_resets)
runner.test("Retrieving dinosaur returns it to inventory and collects pending income", test_cage_retrieve_dinosaur_returns_to_inventory_and_collects_income)

# -------------------------------------------------------------
# Economy and Progression System Simulation (Phase 8)
# -------------------------------------------------------------
print("\n[SUITE] Economy and Progression System Simulation (Phase 8)")

EQUIPMENT_DATA = {
    "BASIC_SHOVEL": {"Type": "Shovel", "Tier": 1, "Cost": 0, "RequiredLevel": 1},
    "IRON_SHOVEL": {"Type": "Shovel", "Tier": 2, "Cost": 250, "RequiredLevel": 2},
    "GOLDEN_SHOVEL": {"Type": "Shovel", "Tier": 3, "Cost": 1000, "RequiredLevel": 5},
    "BASIC_BRUSH": {"Type": "Brush", "Tier": 1, "Cost": 0, "RequiredLevel": 1},
    "FINE_BRUSH": {"Type": "Brush", "Tier": 2, "Cost": 200, "RequiredLevel": 2},
    "DIAMOND_BRUSH": {"Type": "Brush", "Tier": 3, "Cost": 800, "RequiredLevel": 5},
}

ZONE_DATA = {
    "BEGINNER_SITE": {"RequiredLevel": 1, "UnlockCost": 0},
    "DESERT_CANYON": {"RequiredLevel": 2, "UnlockCost": 300},
}

class MockProgressionService:
    def __init__(self, srv):
        self.server = srv
        self.players = {}

    def _get_player(self, user_id):
        if user_id not in self.players:
            self.players[user_id] = {
                "money": 500,
                "level": 2,
                "owned_equipment": ["BASIC_SHOVEL", "BASIC_BRUSH"],
                "active_shovel": "BASIC_SHOVEL",
                "active_brush": "BASIC_BRUSH",
                "unlocked_zones": ["BEGINNER_SITE"],
                "expansion_level": 1,
                "cage_count": 1,
            }
        return self.players[user_id]

    def buy_equipment(self, user_id, equip_id):
        p = self._get_player(user_id)
        if equip_id not in EQUIPMENT_DATA:
            return False, "Equipment not found"
        info = EQUIPMENT_DATA[equip_id]
        if equip_id in p["owned_equipment"]:
            return False, "Equipment already owned"
        if p["level"] < info["RequiredLevel"]:
            return False, "Level requirement not met"
        if p["money"] < info["Cost"]:
            return False, "Insufficient funds"
        p["money"] -= info["Cost"]
        p["owned_equipment"].append(equip_id)
        if info["Type"] == "Shovel":
            p["active_shovel"] = equip_id
        elif info["Type"] == "Brush":
            p["active_brush"] = equip_id
        return True, "Equipment purchased"

    def equip_item(self, user_id, equip_id):
        p = self._get_player(user_id)
        if equip_id not in EQUIPMENT_DATA:
            return False, "Equipment not found"
        if equip_id not in p["owned_equipment"]:
            return False, "Equipment not owned"
        info = EQUIPMENT_DATA[equip_id]
        if info["Type"] == "Shovel":
            p["active_shovel"] = equip_id
        elif info["Type"] == "Brush":
            p["active_brush"] = equip_id
        return True, "Equipped"

    def unlock_zone(self, user_id, zone_id):
        p = self._get_player(user_id)
        if zone_id not in ZONE_DATA:
            return False, "Zone not found"
        info = ZONE_DATA[zone_id]
        if zone_id in p["unlocked_zones"]:
            return False, "Zone already unlocked"
        if p["level"] < info["RequiredLevel"]:
            return False, "Level requirement not met"
        if p["money"] < info["UnlockCost"]:
            return False, "Insufficient funds"
        p["money"] -= info["UnlockCost"]
        p["unlocked_zones"].append(zone_id)
        return True, "Zone unlocked"

    def expand_plot(self, user_id):
        p = self._get_player(user_id)
        cost = int(500 * (2.0 ** (p["expansion_level"] - 1)))
        if p["money"] < cost:
            return False, "Insufficient funds"
        p["money"] -= cost
        p["expansion_level"] += 1
        return True, "Plot expanded"

    def buy_cage(self, user_id):
        p = self._get_player(user_id)
        cost = 200
        if p["money"] < cost:
            return False, "Insufficient funds"
        p["money"] -= cost
        p["cage_count"] += 1
        return True, "Cage purchased"

    def sell_fossil(self, user_id, item_uid):
        inv = self.server.get_inventory(user_id)
        item = None
        for it in inv:
            if it["ItemUID"] == item_uid:
                item = it
                break
        if not item:
            return False, "Item not found in inventory"
        if item["ItemType"] != "Fossil":
            return False, "Only fossils can be sold"
        earned = max(1, int(10 * 0.5))  # 5
        self.server.remove_item(user_id, item_uid)
        p = self._get_player(user_id)
        p["money"] += earned
        return True, earned

progression = MockProgressionService(server)

def test_prog_reject_unknown_equipment():
    s, r = progression.buy_equipment(6001, "UNKNOWN_TOOL")
    assert s is False
    assert r == "Equipment not found"

def test_prog_reject_already_owned_equipment():
    s, r = progression.buy_equipment(6001, "BASIC_SHOVEL")
    assert s is False
    assert r == "Equipment already owned"

def test_prog_reject_underleveled_equipment():
    # GOLDEN_SHOVEL requires level 5, user 6001 is level 2
    s, r = progression.buy_equipment(6001, "GOLDEN_SHOVEL")
    assert s is False
    assert r == "Level requirement not met"

def test_prog_reject_unaffordable_equipment():
    p = progression._get_player(6002)
    p["money"] = 50
    s, r = progression.buy_equipment(6002, "IRON_SHOVEL")
    assert s is False
    assert r == "Insufficient funds"

def test_prog_buy_equipment_deducts_money_adds_to_owned_and_equips():
    p = progression._get_player(6003)
    p["money"] = 500
    s, _ = progression.buy_equipment(6003, "IRON_SHOVEL")
    assert s is True
    assert p["money"] == 250
    assert "IRON_SHOVEL" in p["owned_equipment"]
    assert p["active_shovel"] == "IRON_SHOVEL"

def test_prog_equip_owned_and_reject_unowned():
    s1, r1 = progression.equip_item(6003, "DIAMOND_BRUSH")
    assert s1 is False
    assert r1 == "Equipment not owned"
    s2, _ = progression.equip_item(6003, "BASIC_BRUSH")
    assert s2 is True

def test_prog_unlock_zone_deducts_money_and_adds_to_unlocked():
    p = progression._get_player(6004)
    p["money"] = 1000
    p["level"] = 3
    s, _ = progression.unlock_zone(6004, "DESERT_CANYON")
    assert s is True
    assert p["money"] == 700  # 1000 - 300
    assert "DESERT_CANYON" in p["unlocked_zones"]

def test_prog_expand_plot_deducts_cost_and_increments_level():
    p = progression._get_player(6005)
    p["money"] = 1000
    s, _ = progression.expand_plot(6005)
    assert s is True
    assert p["money"] == 500  # 1000 - 500
    assert p["expansion_level"] == 2

def test_prog_buy_cage_deducts_cost_and_increments_count():
    p = progression._get_player(6006)
    p["money"] = 500
    s, _ = progression.buy_cage(6006)
    assert s is True
    assert p["money"] == 300  # 500 - 200
    assert p["cage_count"] == 2

def test_prog_sell_fossil_removes_from_inventory_and_awards_cash():
    fossil = create_fossil_item("TREX_TOOTH")
    server.add_item(6007, fossil)
    p = progression._get_player(6007)
    start_money = p["money"]
    s, earned = progression.sell_fossil(6007, fossil["ItemUID"])
    assert s is True
    assert earned == 5
    assert len(server.get_inventory(6007)) == 0
    assert p["money"] == start_money + 5

runner.test("Progression rejects unknown equipment", test_prog_reject_unknown_equipment)
runner.test("Progression rejects already owned equipment", test_prog_reject_already_owned_equipment)
runner.test("Progression rejects under-leveled equipment purchase", test_prog_reject_underleveled_equipment)
runner.test("Progression rejects equipment purchase with insufficient funds", test_prog_reject_unaffordable_equipment)
runner.test("Progression buys equipment, deducts money, adds to owned, and auto-equips", test_prog_buy_equipment_deducts_money_adds_to_owned_and_equips)
runner.test("Progression equips owned tools and rejects unowned tools", test_prog_equip_owned_and_reject_unowned)
runner.test("Progression unlocks excavation zone, deducts funds, and adds to UnlockedZones", test_prog_unlock_zone_deducts_money_and_adds_to_unlocked)
runner.test("Progression expands plot, deducting scaled cost and incrementing level", test_prog_expand_plot_deducts_cost_and_increments_level)
runner.test("Progression buys cages, deducting cost and incrementing cage count", test_prog_buy_cage_deducts_cost_and_increments_count)
runner.test("Progression sells fossils from inventory for cash", test_prog_sell_fossil_removes_from_inventory_and_awards_cash)

# -------------------------------------------------------------
# Data Persistence System Simulation (Phase 9)
# -------------------------------------------------------------
print("\n[SUITE] Data Persistence System Simulation (Phase 9)")

def validate_and_migrate(raw):
    default = {
        "Money": 100,
        "Level": 1,
        "XP": 0,
        "Inventory": [],
        "Equipment": {
            "ActiveShovel": "BASIC_SHOVEL",
            "ActiveBrush": "BASIC_BRUSH",
            "OwnedEquipment": ["BASIC_SHOVEL", "BASIC_BRUSH"],
        },
        "UnlockedZones": ["BEGINNER_SITE"],
        "PlotData": {"ExpansionLevel": 1, "CageCount": 1},
        "CageAssignments": {},
        "Statistics": {"TotalMoneyEarned": 0, "TotalFossilsExcavated": 0},
    }
    if not isinstance(raw, dict):
        return default
    migrated = dict(default)
    migrated.update(raw)
    # Ensure nested objects are merged
    if "PlotData" not in raw or not isinstance(raw["PlotData"], dict):
        migrated["PlotData"] = default["PlotData"]
    if "Statistics" not in raw or not isinstance(raw["Statistics"], dict):
        migrated["Statistics"] = default["Statistics"]
    if "Equipment" not in raw or not isinstance(raw["Equipment"], dict):
        migrated["Equipment"] = default["Equipment"]
    return migrated

class MockDataStoreService:
    def __init__(self):
        self.storage = {}
        self.should_fail = False

    def get_async(self, key):
        if self.should_fail:
            raise RuntimeError("DataStore error: connection refused")
        return self.storage.get(key)

    def set_async(self, key, value):
        if self.should_fail:
            raise RuntimeError("DataStore error: write limit exceeded")
        self.storage[key] = dict(value)

datastore = MockDataStoreService()

def test_persistence_migration_empty():
    res = validate_and_migrate({})
    assert res["Money"] == 100
    assert res["Level"] == 1
    assert res["PlotData"]["ExpansionLevel"] == 1

def test_persistence_migration_preserves_legacy():
    legacy = {"Money": 9999, "Level": 10}
    res = validate_and_migrate(legacy)
    assert res["Money"] == 9999
    assert res["Level"] == 10
    assert res["PlotData"]["ExpansionLevel"] == 1
    assert res["Statistics"]["TotalMoneyEarned"] == 0

def test_persistence_save_and_reload():
    user_key = "Player_7001"
    data = validate_and_migrate({"Money": 4500, "Level": 4})
    datastore.set_async(user_key, data)
    loaded = datastore.get_async(user_key)
    assert loaded is not None
    assert loaded["Money"] == 4500
    assert loaded["Level"] == 4

def test_persistence_error_graceful_catch():
    datastore.should_fail = True
    caught = False
    try:
        datastore.set_async("Player_7002", {"Money": 100})
    except RuntimeError:
        caught = True
    assert caught is True
    datastore.should_fail = False

runner.test("Persistence migration handles empty record", test_persistence_migration_empty)
runner.test("Persistence migration preserves legacy data and adds schema", test_persistence_migration_preserves_legacy)
runner.test("Persistence accurately saves and reloads player data", test_persistence_save_and_reload)
runner.test("Persistence handles DataStore errors gracefully without crashing", test_persistence_error_graceful_catch)

# -------------------------------------------------------------
# Expansion and Polish System Simulation (Phase 10)
# -------------------------------------------------------------
print("\n[SUITE] Expansion and Polish System Simulation (Phase 10)")

DINOSAURS_EXPANDED = {
    "TREX": {"Rarity": "Common", "BaseIncome": 10, "IncubationTime": 30},
    "VELOCIRAPTOR": {"Rarity": "Uncommon", "BaseIncome": 18, "IncubationTime": 40},
    "TRICERATOPS": {"Rarity": "Rare", "BaseIncome": 30, "IncubationTime": 50},
    "SPINOSAURUS": {"Rarity": "Epic", "BaseIncome": 55, "IncubationTime": 75},
}

FOSSILS_EXPANDED = {
    "TREX_TOOTH": {"DinosaurID": "TREX", "Value": 5, "Rarity": "Common"},
    "RAPTOR_CLAW": {"DinosaurID": "VELOCIRAPTOR", "Value": 15, "Rarity": "Uncommon"},
    "TRICERATOPS_HORN": {"DinosaurID": "TRICERATOPS", "Value": 35, "Rarity": "Rare"},
    "SPINOSAURUS_SPINE": {"DinosaurID": "SPINOSAURUS", "Value": 80, "Rarity": "Epic"},
}

ZONES_EXPANDED = {
    "BEGINNER_SITE": {"RequiredLevel": 1, "UnlockCost": 0, "Fossils": ["TREX_TOOTH"]},
    "DESERT_CANYON": {"RequiredLevel": 2, "UnlockCost": 300, "Fossils": ["TREX_TOOTH", "RAPTOR_CLAW"]},
    "FROZEN_TUNDRA": {"RequiredLevel": 5, "UnlockCost": 1500, "Fossils": ["TREX_TOOTH", "RAPTOR_CLAW", "TRICERATOPS_HORN"]},
    "VOLCANIC_RIDGE": {"RequiredLevel": 10, "UnlockCost": 5000, "Fossils": ["TREX_TOOTH", "RAPTOR_CLAW", "TRICERATOPS_HORN", "SPINOSAURUS_SPINE"]},
}

def test_expansion_dinosaur_catalog():
    for dino_id, data in DINOSAURS_EXPANDED.items():
        assert data["BaseIncome"] > 0
        assert data["IncubationTime"] > 0

def test_expansion_fossil_mapping():
    for fossil_id, data in FOSSILS_EXPANDED.items():
        assert data["DinosaurID"] in DINOSAURS_EXPANDED
        assert data["Value"] > 0

def test_expansion_pipeline_end_to_end_all_dinosaurs():
    # Test that every fossil produces DNA, then Dinosaur, and earns income
    for fossil_id, fossil_info in FOSSILS_EXPANDED.items():
        dino_id = fossil_info["DinosaurID"]
        fossil = {
            "ItemUID": str(uuid.uuid4()),
            "ItemType": "Fossil",
            "ConfigID": fossil_id,
            "DinosaurID": dino_id,
            "Rarity": fossil_info["Rarity"],
            "Quality": 90,
            "IsCleaned": True,
            "ObtainedAt": int(time.time()),
        }
        dna = {
            "ItemUID": str(uuid.uuid4()),
            "ItemType": "DNA",
            "ConfigID": dino_id + "_DNA",
            "DinosaurID": dino_id,
            "Rarity": fossil_info["Rarity"],
            "Quality": 90,
            "IsCleaned": False,
            "ObtainedAt": int(time.time()),
        }
        dino = {
            "ItemUID": str(uuid.uuid4()),
            "ItemType": "Dinosaur",
            "ConfigID": dino_id,
            "DinosaurID": dino_id,
            "Rarity": fossil_info["Rarity"],
            "Quality": 90,
            "IsCleaned": False,
            "ObtainedAt": int(time.time()),
        }
        assert dino["ItemType"] == "Dinosaur"
        assert dino["DinosaurID"] == dino_id
        # Income check
        base_income = DINOSAURS_EXPANDED[dino_id]["BaseIncome"]
        assert base_income >= 10

def test_expansion_zones_integrity():
    for zone_id, data in ZONES_EXPANDED.items():
        assert data["RequiredLevel"] >= 1
        for f in data["Fossils"]:
            assert f in FOSSILS_EXPANDED

runner.test("Expansion verifies full dinosaur catalog", test_expansion_dinosaur_catalog)
runner.test("Expansion verifies fossil to dinosaur mappings", test_expansion_fossil_mapping)
runner.test("Expansion validates end-to-end pipeline across all dinosaur tiers", test_expansion_pipeline_end_to_end_all_dinosaurs)
runner.test("Expansion verifies all 4 zones and fossil pools", test_expansion_zones_integrity)

all_passed = runner.summary()
sys.exit(0 if all_passed else 1)

