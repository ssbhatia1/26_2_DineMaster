package com.dinemaster;

import java.sql.Connection;
import java.sql.DriverManager;

public class DBConnection {

    public static void main(String[] args) {

        String URL = "jdbc:postgresql://ep-odd-recipe-a7c0q9ag-pooler.ap-southeast-2.aws.neon.tech/dine_master?sslmode=require&channelBinding=require";
        String USER = System.getenv("DB_USERNAME");
        String PASS = System.getenv("DB_PASSWORD");

        try (Connection con = DriverManager.getConnection(URL, USER, PASS)) {
            System.out.println("Database connected successfully!");
        } catch (Exception e) {
            System.out.println("Connection failed: " + e.getMessage());
        }
    }
}