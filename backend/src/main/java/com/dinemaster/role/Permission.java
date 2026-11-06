package com.dinemaster.role;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "permissions")
public class Permission {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(nullable = false, unique = true, length = 100)
    private String code;
    @Column(length = 255)
    private String description;

    protected Permission() { }
    public Permission(String code) { this.code = code; this.description = code.replace(':', ' '); }
    public Long getId() { return id; }
    public String getCode() { return code; }
}
