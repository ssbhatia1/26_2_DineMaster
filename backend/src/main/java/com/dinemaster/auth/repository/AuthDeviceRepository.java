package com.dinemaster.auth.repository;

import com.dinemaster.auth.entity.AuthDevice;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.UUID;

public interface AuthDeviceRepository extends JpaRepository<AuthDevice, UUID> {
    List<AuthDevice> findAllByUserIdAndActiveTrue(Long userId);
}
