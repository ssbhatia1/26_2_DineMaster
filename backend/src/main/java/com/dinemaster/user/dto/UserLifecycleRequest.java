package com.dinemaster.user.dto;

import jakarta.validation.constraints.Size;

public record UserLifecycleRequest(@Size(max = 500) String reason) { }
