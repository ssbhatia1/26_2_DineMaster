package com.dinemaster.config;

import com.dinemaster.security.BranchScopeInterceptor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebMvcConfig implements WebMvcConfigurer {
    private final BranchScopeInterceptor branchScopeInterceptor;
    public WebMvcConfig(BranchScopeInterceptor branchScopeInterceptor) {
        this.branchScopeInterceptor = branchScopeInterceptor;
    }
    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(branchScopeInterceptor).addPathPatterns("/api/v1/**");
    }
}
