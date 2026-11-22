package com.ztsec.ghost.portal.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;

/** API chain uses basic auth with a readable CSRF cookie; pages chain uses form login. */
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    private static final int MIN_PASSWORD = 12;

    @Bean
    PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }

    @Bean
    UserDetailsService users(
            @Value("${ZT_OPERATOR_USERNAME:}") String operator,
            @Value("${ZT_OPERATOR_PASSWORD:}") String operatorPassword,
            @Value("${ZT_ASSET_USERNAME:}") String asset,
            @Value("${ZT_ASSET_PASSWORD:}") String assetPassword) {

        if (operator.isBlank() || asset.isBlank()) {
            throw new IllegalStateException("ZT_OPERATOR_USERNAME and ZT_ASSET_USERNAME are required.");
        }
        if (operatorPassword.length() < MIN_PASSWORD || assetPassword.length() < MIN_PASSWORD) {
            throw new IllegalStateException("Passwords must be at least " + MIN_PASSWORD + " characters.");
        }
        if (operatorPassword.equals(assetPassword)) {
            throw new IllegalStateException("Operator and asset passwords must differ.");
        }

        PasswordEncoder encoder = passwordEncoder();
        return new InMemoryUserDetailsManager(
                User.withUsername(operator).password(encoder.encode(operatorPassword)).roles("OPERATOR").build(),
                User.withUsername(asset).password(encoder.encode(assetPassword)).roles("ASSET").build());
    }

    @Bean
    SecurityFilterChain apiChain(HttpSecurity http) throws Exception {
        http.securityMatcher("/api/zt01/**")
                .csrf(csrf -> csrf.csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
                        .ignoringRequestMatchers("/api/zt01/case"))
                .headers(headers -> headers
                        .contentTypeOptions(Customizer.withDefaults())
                        .frameOptions(Customizer.withDefaults())
                        .httpStrictTransportSecurity(Customizer.withDefaults()))
                .authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
                .httpBasic(Customizer.withDefaults());
        return http.build();
    }

    @Bean
    SecurityFilterChain pageChain(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests(auth -> auth
                        .requestMatchers("/", "/ghost.html", "/takeover.html", "/zt01.css",
                                "/takeover.js", "/comms.js", "/vault.js", "/login",
                                "/actuator/health").permitAll()
                        .anyRequest().authenticated())
                .formLogin(Customizer.withDefaults())
                .logout(Customizer.withDefaults())
                .headers(headers -> headers
                        .contentTypeOptions(Customizer.withDefaults())
                        .frameOptions(Customizer.withDefaults()));
        return http.build();
    }
}
