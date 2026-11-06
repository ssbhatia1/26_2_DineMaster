package com.dinemaster.user.dto;

import jakarta.validation.constraints.Size;

public record UserDeactivationRequest(@Size(max = 500) String reason) { }
