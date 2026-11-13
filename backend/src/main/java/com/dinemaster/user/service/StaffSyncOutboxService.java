package com.dinemaster.user.service;

import com.dinemaster.user.entity.User;
import com.dinemaster.user.repository.UserBranchRepository;
import com.dinemaster.user.repository.UserRoleRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.LinkedHashMap;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/** Stores committed staff snapshots for the Edge sync publisher to deliver. */
@Service
public class StaffSyncOutboxService {
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final UserBranchRepository branches;
    private final UserRoleRepository roles;

    public StaffSyncOutboxService(JdbcTemplate jdbc, ObjectMapper mapper,
            UserBranchRepository branches, UserRoleRepository roles) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.branches = branches;
        this.roles = roles;
    }

    public void record(User user, String eventType) {
        LinkedHashMap<String, Object> payload = new LinkedHashMap<>();
        payload.put("userId", user.getId());
        payload.put("tenantId", user.getTenantId());
        payload.put("username", user.getUsername());
        payload.put("fullName", user.getName());
        payload.put("roleCodes", roles.findRoleCodes(user.getId()));
        payload.put("branchIds", branches.findBranchIds(user.getId()));
        payload.put("active", user.isActive());
        payload.put("permissionVersion", user.getPermissionVersion());
        payload.put("mustChangePassword", user.isMustChangePassword());
        try {
            jdbc.update("insert into staff_sync_outbox (tenant_id, user_id, event_type, payload) values (?, ?, ?, ?)",
                    user.getTenantId(), user.getId(), eventType, mapper.writeValueAsString(payload));
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException("Unable to serialize staff sync event", exception);
        }
    }
}
