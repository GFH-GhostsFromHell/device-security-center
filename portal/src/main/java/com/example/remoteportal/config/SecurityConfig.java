package com.example.remoteportal.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

/** Standalone deployment only. Separate operator and owner credentials are required. */
@Configuration
public class SecurityConfig {
    @Bean
    PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }

    @Bean
    UserDetailsService users(
            @Value("${DEVICE_ADMIN_USERNAME:}") String admin,
            @Value("${DEVICE_ADMIN_PASSWORD:}") String adminPassword,
            @Value("${DEVICE_OWNER_USERNAME:}") String owner,
            @Value("${DEVICE_OWNER_PASSWORD:}") String ownerPassword,
            PasswordEncoder encoder) {
        if (admin.isBlank() || owner.isBlank()
                || adminPassword.length() < 12 || ownerPassword.length() < 12
                || admin.equalsIgnoreCase(owner) || adminPassword.equals(ownerPassword)) {
            throw new IllegalStateException(
                "Configure distinct DEVICE_ADMIN_USERNAME, DEVICE_ADMIN_PASSWORD, "
                + "DEVICE_OWNER_USERNAME and DEVICE_OWNER_PASSWORD (12+ characters).");
        }
        return new InMemoryUserDetailsManager(
            User.withUsername(admin).password(encoder.encode(adminPassword)).roles("ADMIN").build(),
            User.withUsername(owner).password(encoder.encode(ownerPassword)).roles("CLIENT").build());
    }

    @Bean
    SecurityFilterChain security(HttpSecurity http) throws Exception {
        http.csrf(csrf -> csrf.ignoringRequestMatchers("/api/device-security/**"))
            .authorizeHttpRequests(a -> a
                .requestMatchers("/actuator/health").permitAll()
                .anyRequest().authenticated())
            .formLogin(Customizer.withDefaults())
            .httpBasic(Customizer.withDefaults());
        return http.build();
    }
}
