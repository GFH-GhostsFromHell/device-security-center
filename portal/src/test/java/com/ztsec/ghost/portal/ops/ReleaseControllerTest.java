package com.ztsec.ghost.portal.ops;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "ZT_OPERATOR_USERNAME=operator",
        "ZT_OPERATOR_PASSWORD=operator-password-1",
        "ZT_ASSET_USERNAME=asset",
        "ZT_ASSET_PASSWORD=asset-password-12"
})
@AutoConfigureMockMvc
class ReleaseControllerTest {
    @Autowired
    MockMvc mvc;

    @Test
    void approveRequiresOperator() throws Exception {
        mvc.perform(post("/api/zt01/release/MISSING")
                        .with(httpBasic("asset", "asset-password-12"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"wrappedKey\":\"abc\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void approveOnUnknownCaseIsNotFound() throws Exception {
        mvc.perform(post("/api/zt01/release/MISSING")
                        .with(httpBasic("operator", "operator-password-1"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"wrappedKey\":\"abc\"}"))
                .andExpect(status().isNotFound());
    }
}
