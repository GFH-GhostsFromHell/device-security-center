package com.ztsec.ghost;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

class CaseLedgerTest {
    @TempDir
    Path root;

    @Test
    void stateSurvivesReload() throws Exception {
        CaseLedger ledger = CaseLedger.create(root, "ABC123", "label");
        ledger.state(CaseState.ARMED);
        CaseLedger reloaded = CaseLedger.load(CaseLedger.locate(root));
        assertEquals(CaseState.ARMED, reloaded.state());
        assertEquals("ABC123", reloaded.caseId());
    }

    @Test
    void unknownStateFallsBackToDraft() throws Exception {
        CaseLedger ledger = CaseLedger.create(root, "ABC123", "label");
        ledger.put("state", "NONSENSE");
        assertEquals(CaseState.DRAFT, CaseLedger.load(CaseLedger.locate(root)).state());
    }
}
