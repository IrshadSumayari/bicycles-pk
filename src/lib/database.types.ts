export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      app_settings: {
        Row: {
          auto_backup: boolean | null;
          cash_variance_alert: number;
          cod_enabled: boolean;
          cod_max_total: number | null;
          created_at: string;
          currency: string | null;
          delivery_fee: number;
          free_delivery_over: number | null;
          id: string;
          interface_mode: string | null;
          invoice_counter: number | null;
          invoice_prefix: string | null;
          max_cashier_discount_percent: number;
          ntn: string | null;
          online_card_enabled: boolean;
          online_hold_minutes: number;
          online_max_open_cod_orders: number;
          online_max_pending_orders: number;
          receipt_footer: string | null;
          receipt_header: string | null;
          receipt_printer: boolean | null;
          return_window_days: number;
          store_address: string | null;
          store_email: string | null;
          store_logo: string | null;
          store_name: string | null;
          store_phone: string | null;
          strn: string | null;
          tax_rate: number | null;
          theme: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          auto_backup?: boolean | null;
          cash_variance_alert?: number;
          cod_enabled?: boolean;
          cod_max_total?: number | null;
          created_at?: string;
          currency?: string | null;
          delivery_fee?: number;
          free_delivery_over?: number | null;
          id?: string;
          interface_mode?: string | null;
          invoice_counter?: number | null;
          invoice_prefix?: string | null;
          max_cashier_discount_percent?: number;
          ntn?: string | null;
          online_card_enabled?: boolean;
          online_hold_minutes?: number;
          online_max_open_cod_orders?: number;
          online_max_pending_orders?: number;
          receipt_footer?: string | null;
          receipt_header?: string | null;
          receipt_printer?: boolean | null;
          return_window_days?: number;
          store_address?: string | null;
          store_email?: string | null;
          store_logo?: string | null;
          store_name?: string | null;
          store_phone?: string | null;
          strn?: string | null;
          tax_rate?: number | null;
          theme?: string | null;
          updated_at?: string;
        };
        Update: {
          auto_backup?: boolean | null;
          cash_variance_alert?: number;
          cod_enabled?: boolean;
          cod_max_total?: number | null;
          created_at?: string;
          currency?: string | null;
          delivery_fee?: number;
          free_delivery_over?: number | null;
          id?: string;
          interface_mode?: string | null;
          invoice_counter?: number | null;
          invoice_prefix?: string | null;
          max_cashier_discount_percent?: number;
          ntn?: string | null;
          online_card_enabled?: boolean;
          online_hold_minutes?: number;
          online_max_open_cod_orders?: number;
          online_max_pending_orders?: number;
          receipt_footer?: string | null;
          receipt_header?: string | null;
          receipt_printer?: boolean | null;
          return_window_days?: number;
          store_address?: string | null;
          store_email?: string | null;
          store_logo?: string | null;
          store_name?: string | null;
          store_phone?: string | null;
          strn?: string | null;
          tax_rate?: number | null;
          theme?: string | null;
          updated_at?: string;
        };
        Relationships: [];
      };
      barcodes: {
        Row: {
          code: string;
          created_at: string;
          variant_id: string;
        };
        ComputedFields: never;
        Insert: {
          code: string;
          created_at?: string;
          variant_id: string;
        };
        Update: {
          code?: string;
          created_at?: string;
          variant_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "barcodes_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "barcodes_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      branch_memberships: {
        Row: {
          branch_id: string;
          created_at: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          created_at?: string;
          user_id: string;
        };
        Update: {
          branch_id?: string;
          created_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "branch_memberships_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "branch_memberships_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      branches: {
        Row: {
          active: boolean;
          address: string | null;
          code: string;
          created_at: string;
          currency: string;
          id: string;
          name: string;
          phone: string | null;
          timezone: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          address?: string | null;
          code: string;
          created_at?: string;
          currency?: string;
          id?: string;
          name: string;
          phone?: string | null;
          timezone?: string;
          updated_at?: string;
        };
        Update: {
          active?: boolean;
          address?: string | null;
          code?: string;
          created_at?: string;
          currency?: string;
          id?: string;
          name?: string;
          phone?: string | null;
          timezone?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      business_lookups: {
        Row: {
          active: boolean;
          id: string;
          kind: string;
          value: string;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          id?: string;
          kind: string;
          value: string;
        };
        Update: {
          active?: boolean;
          id?: string;
          kind?: string;
          value?: string;
        };
        Relationships: [];
      };
      cash_movements: {
        Row: {
          amount: number;
          created_at: string;
          created_by: string | null;
          id: number;
          movement_type: string;
          payment_id: string | null;
          reason: string | null;
          session_id: string;
        };
        ComputedFields: never;
        Insert: {
          amount: number;
          created_at?: string;
          created_by?: string | null;
          id?: never;
          movement_type: string;
          payment_id?: string | null;
          reason?: string | null;
          session_id: string;
        };
        Update: {
          amount?: number;
          created_at?: string;
          created_by?: string | null;
          id?: never;
          movement_type?: string;
          payment_id?: string | null;
          reason?: string | null;
          session_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "cash_movements_session_id_fkey";
            columns: ["session_id"];
            isOneToOne: false;
            referencedRelation: "cash_sessions";
            referencedColumns: ["id"];
          },
        ];
      };
      cash_sessions: {
        Row: {
          branch_id: string;
          closed_at: string | null;
          closed_by: string | null;
          closing_notes: string | null;
          counted_cash: number | null;
          expected_cash: number | null;
          id: string;
          location_id: string;
          opened_at: string;
          opening_float: number;
          session_no: string;
          status: string;
          user_id: string;
          variance: number | null;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          closed_at?: string | null;
          closed_by?: string | null;
          closing_notes?: string | null;
          counted_cash?: number | null;
          expected_cash?: number | null;
          id?: string;
          location_id: string;
          opened_at?: string;
          opening_float: number;
          session_no: string;
          status?: string;
          user_id: string;
          variance?: number | null;
        };
        Update: {
          branch_id?: string;
          closed_at?: string | null;
          closed_by?: string | null;
          closing_notes?: string | null;
          counted_cash?: number | null;
          expected_cash?: number | null;
          id?: string;
          location_id?: string;
          opened_at?: string;
          opening_float?: number;
          session_no?: string;
          status?: string;
          user_id?: string;
          variance?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "cash_sessions_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "cash_sessions_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "cash_sessions_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      categories: {
        Row: {
          active: boolean;
          created_at: string;
          description: string | null;
          id: string;
          name: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          created_at?: string;
          description?: string | null;
          id?: string;
          name: string;
          updated_at?: string;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          description?: string | null;
          id?: string;
          name?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      collection_styles: {
        Row: {
          collection_id: string;
          sort_order: number;
          style_id: string;
        };
        ComputedFields: never;
        Insert: {
          collection_id: string;
          sort_order?: number;
          style_id: string;
        };
        Update: {
          collection_id?: string;
          sort_order?: number;
          style_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "collection_styles_collection_id_fkey";
            columns: ["collection_id"];
            isOneToOne: false;
            referencedRelation: "collections";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "collection_styles_style_id_fkey";
            columns: ["style_id"];
            isOneToOne: false;
            referencedRelation: "product_styles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "collection_styles_style_id_fkey";
            columns: ["style_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["style_id"];
          },
        ];
      };
      collections: {
        Row: {
          description: string | null;
          ends_at: string | null;
          hero_image_path: string | null;
          id: string;
          name: string;
          published: boolean;
          slug: string;
          sort_order: number;
          starts_at: string | null;
        };
        ComputedFields: never;
        Insert: {
          description?: string | null;
          ends_at?: string | null;
          hero_image_path?: string | null;
          id?: string;
          name: string;
          published?: boolean;
          slug: string;
          sort_order?: number;
          starts_at?: string | null;
        };
        Update: {
          description?: string | null;
          ends_at?: string | null;
          hero_image_path?: string | null;
          id?: string;
          name?: string;
          published?: boolean;
          slug?: string;
          sort_order?: number;
          starts_at?: string | null;
        };
        Relationships: [];
      };
      commission_entries: {
        Row: {
          amount: number;
          branch_id: string;
          created_at: string;
          created_by: string | null;
          id: string;
          kind: string;
          note: string | null;
          request_id: string | null;
          return_line_id: string | null;
          sale_id: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          amount: number;
          branch_id: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          kind: string;
          note?: string | null;
          request_id?: string | null;
          return_line_id?: string | null;
          sale_id?: string | null;
          user_id: string;
        };
        Update: {
          amount?: number;
          branch_id?: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          kind?: string;
          note?: string | null;
          request_id?: string | null;
          return_line_id?: string | null;
          sale_id?: string | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "commission_entries_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "commission_entries_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "commission_entries_return_line_id_fkey";
            columns: ["return_line_id"];
            isOneToOne: true;
            referencedRelation: "return_lines";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "commission_entries_sale_id_fkey";
            columns: ["sale_id"];
            isOneToOne: false;
            referencedRelation: "sale_commissions";
            referencedColumns: ["sale_id"];
          },
          {
            foreignKeyName: "commission_entries_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      commission_rules: {
        Row: {
          branch_id: string;
          enabled: boolean;
          kind: string;
          rate: number;
          updated_at: string;
          updated_by: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          enabled?: boolean;
          kind: string;
          rate: number;
          updated_at?: string;
          updated_by?: string | null;
          user_id: string;
        };
        Update: {
          branch_id?: string;
          enabled?: boolean;
          kind?: string;
          rate?: number;
          updated_at?: string;
          updated_by?: string | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "commission_rules_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "commission_rules_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "commission_rules_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      courier_returns: {
        Row: {
          courier_cost: number;
          created_at: string;
          created_by: string;
          id: string;
          order_id: string;
          reason: string;
          return_id: string;
        };
        ComputedFields: never;
        Insert: {
          courier_cost: number;
          created_at?: string;
          created_by?: string;
          id?: string;
          order_id: string;
          reason: string;
          return_id: string;
        };
        Update: {
          courier_cost?: number;
          created_at?: string;
          created_by?: string;
          id?: string;
          order_id?: string;
          reason?: string;
          return_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "courier_returns_order_id_fkey";
            columns: ["order_id"];
            isOneToOne: true;
            referencedRelation: "online_orders";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "courier_returns_return_id_fkey";
            columns: ["return_id"];
            isOneToOne: true;
            referencedRelation: "returns";
            referencedColumns: ["id"];
          },
        ];
      };
      customer_accounts: {
        Row: {
          created_at: string;
          customer_id: string | null;
          email: string | null;
          email_consent_at: string | null;
          email_marketing_consent: boolean | null;
          full_name: string | null;
          id: string;
          marketing_consent: boolean;
          phone: string | null;
          phone_verified: boolean;
          sms_consent_at: string | null;
          sms_marketing_consent: boolean | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          customer_id?: string | null;
          email?: string | null;
          email_consent_at?: string | null;
          email_marketing_consent?: boolean | null;
          full_name?: string | null;
          id: string;
          marketing_consent?: boolean;
          phone?: string | null;
          phone_verified?: boolean;
          sms_consent_at?: string | null;
          sms_marketing_consent?: boolean | null;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          customer_id?: string | null;
          email?: string | null;
          email_consent_at?: string | null;
          email_marketing_consent?: boolean | null;
          full_name?: string | null;
          id?: string;
          marketing_consent?: boolean;
          phone?: string | null;
          phone_verified?: boolean;
          sms_consent_at?: string | null;
          sms_marketing_consent?: boolean | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "customer_accounts_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
        ];
      };
      customer_ledger: {
        Row: {
          amount: number;
          created_at: string;
          created_by: string | null;
          customer_id: string;
          entry_type: string;
          id: number;
          note: string | null;
          payment_id: string | null;
          return_id: string | null;
          sale_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          amount: number;
          created_at?: string;
          created_by?: string | null;
          customer_id: string;
          entry_type: string;
          id?: never;
          note?: string | null;
          payment_id?: string | null;
          return_id?: string | null;
          sale_id?: string | null;
        };
        Update: {
          amount?: number;
          created_at?: string;
          created_by?: string | null;
          customer_id?: string;
          entry_type?: string;
          id?: never;
          note?: string | null;
          payment_id?: string | null;
          return_id?: string | null;
          sale_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "customer_ledger_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "customer_ledger_payment_header_fkey";
            columns: ["payment_id"];
            isOneToOne: false;
            referencedRelation: "customer_payments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "customer_ledger_return_id_fkey";
            columns: ["return_id"];
            isOneToOne: false;
            referencedRelation: "returns";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "customer_ledger_sale_id_fkey";
            columns: ["sale_id"];
            isOneToOne: false;
            referencedRelation: "sales";
            referencedColumns: ["id"];
          },
        ];
      };
      customer_payments: {
        Row: {
          created_at: string;
          created_by: string | null;
          customer_id: string;
          id: string;
          note: string | null;
          payment_no: string;
          request_id: string;
          total: number;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          customer_id: string;
          id?: string;
          note?: string | null;
          payment_no: string;
          request_id: string;
          total: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          customer_id?: string;
          id?: string;
          note?: string | null;
          payment_no?: string;
          request_id?: string;
          total?: number;
        };
        Relationships: [
          {
            foreignKeyName: "customer_payments_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
        ];
      };
      customers: {
        Row: {
          address: string | null;
          created_at: string;
          credit_limit: number | null;
          credit_used: number | null;
          email: string | null;
          email_consent_at: string | null;
          email_marketing_consent: boolean | null;
          id: string;
          last_purchase: string | null;
          name: string;
          phone: string | null;
          price_tier: string | null;
          sms_consent_at: string | null;
          sms_marketing_consent: boolean | null;
          total_purchases: number | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          address?: string | null;
          created_at?: string;
          credit_limit?: number | null;
          credit_used?: number | null;
          email?: string | null;
          email_consent_at?: string | null;
          email_marketing_consent?: boolean | null;
          id?: string;
          last_purchase?: string | null;
          name: string;
          phone?: string | null;
          price_tier?: string | null;
          sms_consent_at?: string | null;
          sms_marketing_consent?: boolean | null;
          total_purchases?: number | null;
          updated_at?: string;
        };
        Update: {
          address?: string | null;
          created_at?: string;
          credit_limit?: number | null;
          credit_used?: number | null;
          email?: string | null;
          email_consent_at?: string | null;
          email_marketing_consent?: boolean | null;
          id?: string;
          last_purchase?: string | null;
          name?: string;
          phone?: string | null;
          price_tier?: string | null;
          sms_consent_at?: string | null;
          sms_marketing_consent?: boolean | null;
          total_purchases?: number | null;
          updated_at?: string;
        };
        Relationships: [];
      };
      discount_code_redemptions: {
        Row: {
          amount: number;
          code: string;
          code_id: string | null;
          customer_id: string | null;
          id: string;
          redeemed_at: string;
          sale_id: string;
        };
        ComputedFields: never;
        Insert: {
          amount: number;
          code: string;
          code_id?: string | null;
          customer_id?: string | null;
          id?: string;
          redeemed_at?: string;
          sale_id: string;
        };
        Update: {
          amount?: number;
          code?: string;
          code_id?: string | null;
          customer_id?: string | null;
          id?: string;
          redeemed_at?: string;
          sale_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "discount_code_redemptions_code_id_fkey";
            columns: ["code_id"];
            isOneToOne: false;
            referencedRelation: "discount_codes";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "discount_code_redemptions_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "discount_code_redemptions_sale_id_fkey";
            columns: ["sale_id"];
            isOneToOne: true;
            referencedRelation: "sales";
            referencedColumns: ["id"];
          },
        ];
      };
      discount_code_settings: {
        Row: {
          id: boolean;
          updated_at: string;
          updated_by: string | null;
          welcome_enabled: boolean;
          welcome_max_discount: number | null;
          welcome_min_amount: number | null;
          welcome_type: string;
          welcome_valid_days: number;
          welcome_value: number;
        };
        ComputedFields: never;
        Insert: {
          id?: boolean;
          updated_at?: string;
          updated_by?: string | null;
          welcome_enabled?: boolean;
          welcome_max_discount?: number | null;
          welcome_min_amount?: number | null;
          welcome_type?: string;
          welcome_valid_days?: number;
          welcome_value?: number;
        };
        Update: {
          id?: boolean;
          updated_at?: string;
          updated_by?: string | null;
          welcome_enabled?: boolean;
          welcome_max_discount?: number | null;
          welcome_min_amount?: number | null;
          welcome_type?: string;
          welcome_valid_days?: number;
          welcome_value?: number;
        };
        Relationships: [];
      };
      discount_codes: {
        Row: {
          active: boolean;
          code: string;
          created_at: string;
          created_by: string | null;
          customer_id: string | null;
          description: string | null;
          discount_type: string;
          expires_at: string | null;
          id: string;
          kind: string;
          max_discount: number | null;
          max_uses: number | null;
          min_amount: number | null;
          updated_at: string;
          used_count: number;
          valid_from: string;
          value: number;
          discount_code_json: Json | null;
        };
        ComputedFields: "discount_code_json";
        Insert: {
          active?: boolean;
          code: string;
          created_at?: string;
          created_by?: string | null;
          customer_id?: string | null;
          description?: string | null;
          discount_type: string;
          expires_at?: string | null;
          id?: string;
          kind: string;
          max_discount?: number | null;
          max_uses?: number | null;
          min_amount?: number | null;
          updated_at?: string;
          used_count?: number;
          valid_from?: string;
          value: number;
        };
        Update: {
          active?: boolean;
          code?: string;
          created_at?: string;
          created_by?: string | null;
          customer_id?: string | null;
          description?: string | null;
          discount_type?: string;
          expires_at?: string | null;
          id?: string;
          kind?: string;
          max_discount?: number | null;
          max_uses?: number | null;
          min_amount?: number | null;
          updated_at?: string;
          used_count?: number;
          valid_from?: string;
          value?: number;
        };
        Relationships: [
          {
            foreignKeyName: "discount_codes_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
        ];
      };
      discounts: {
        Row: {
          active: boolean | null;
          conditions: Json | null;
          created_at: string;
          description: string | null;
          free_gift_products: string[] | null;
          id: string;
          max_discount: number | null;
          min_amount: number | null;
          name: string;
          type: string;
          updated_at: string;
          valid_days: number[] | null;
          valid_from: string;
          valid_to: string;
          value: number | null;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean | null;
          conditions?: Json | null;
          created_at?: string;
          description?: string | null;
          free_gift_products?: string[] | null;
          id?: string;
          max_discount?: number | null;
          min_amount?: number | null;
          name: string;
          type: string;
          updated_at?: string;
          valid_days?: number[] | null;
          valid_from: string;
          valid_to: string;
          value?: number | null;
        };
        Update: {
          active?: boolean | null;
          conditions?: Json | null;
          created_at?: string;
          description?: string | null;
          free_gift_products?: string[] | null;
          id?: string;
          max_discount?: number | null;
          min_amount?: number | null;
          name?: string;
          type?: string;
          updated_at?: string;
          valid_days?: number[] | null;
          valid_from?: string;
          valid_to?: string;
          value?: number | null;
        };
        Relationships: [];
      };
      goods_receipt_lines: {
        Row: {
          description: string;
          id: string;
          line_cost: number;
          line_no: number;
          quantity: number;
          receipt_id: string;
          unit_cost: number;
          variant_id: string;
        };
        ComputedFields: never;
        Insert: {
          description: string;
          id?: string;
          line_cost: number;
          line_no: number;
          quantity: number;
          receipt_id: string;
          unit_cost: number;
          variant_id: string;
        };
        Update: {
          description?: string;
          id?: string;
          line_cost?: number;
          line_no?: number;
          quantity?: number;
          receipt_id?: string;
          unit_cost?: number;
          variant_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "goods_receipt_lines_receipt_id_fkey";
            columns: ["receipt_id"];
            isOneToOne: false;
            referencedRelation: "goods_receipts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "goods_receipt_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "goods_receipt_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      goods_receipts: {
        Row: {
          branch_id: string;
          created_at: string;
          created_by: string | null;
          id: string;
          location_id: string;
          notes: string | null;
          receipt_no: string;
          received_at: string;
          request_id: string | null;
          supplier_id: string | null;
          supplier_name: string | null;
          supplier_reference: string | null;
          total_cost: number;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          location_id: string;
          notes?: string | null;
          receipt_no: string;
          received_at?: string;
          request_id?: string | null;
          supplier_id?: string | null;
          supplier_name?: string | null;
          supplier_reference?: string | null;
          total_cost?: number;
        };
        Update: {
          branch_id?: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          location_id?: string;
          notes?: string | null;
          receipt_no?: string;
          received_at?: string;
          request_id?: string | null;
          supplier_id?: string | null;
          supplier_name?: string | null;
          supplier_reference?: string | null;
          total_cost?: number;
        };
        Relationships: [
          {
            foreignKeyName: "goods_receipts_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "goods_receipts_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "goods_receipts_supplier_id_fkey";
            columns: ["supplier_id"];
            isOneToOne: false;
            referencedRelation: "suppliers";
            referencedColumns: ["id"];
          },
        ];
      };
      idempotency_keys: {
        Row: {
          created_at: string;
          key: string;
          operation: string;
          result: Json | null;
          user_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          key: string;
          operation: string;
          result?: Json | null;
          user_id?: string | null;
        };
        Update: {
          created_at?: string;
          key?: string;
          operation?: string;
          result?: Json | null;
          user_id?: string | null;
        };
        Relationships: [];
      };
      locations: {
        Row: {
          active: boolean;
          branch_id: string;
          code: string;
          created_at: string;
          id: string;
          kind: string;
          name: string;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          branch_id: string;
          code: string;
          created_at?: string;
          id?: string;
          kind: string;
          name: string;
        };
        Update: {
          active?: boolean;
          branch_id?: string;
          code?: string;
          created_at?: string;
          id?: string;
          kind?: string;
          name?: string;
        };
        Relationships: [
          {
            foreignKeyName: "locations_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
        ];
      };
      lookup_events: {
        Row: {
          action: string;
          created_at: string;
          created_by: string | null;
          id: string;
          kind: string;
          lookup_id: string;
          new_value: Json | null;
          old_value: Json | null;
        };
        ComputedFields: never;
        Insert: {
          action: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          kind: string;
          lookup_id: string;
          new_value?: Json | null;
          old_value?: Json | null;
        };
        Update: {
          action?: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          kind?: string;
          lookup_id?: string;
          new_value?: Json | null;
          old_value?: Json | null;
        };
        Relationships: [
          {
            foreignKeyName: "lookup_events_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      marketing_campaigns: {
        Row: {
          body: string;
          channel: string;
          created_at: string;
          created_by: string;
          id: string;
          name: string;
          status: string;
          subject: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          body: string;
          channel: string;
          created_at?: string;
          created_by?: string;
          id?: string;
          name: string;
          status?: string;
          subject?: string;
          updated_at?: string;
        };
        Update: {
          body?: string;
          channel?: string;
          created_at?: string;
          created_by?: string;
          id?: string;
          name?: string;
          status?: string;
          subject?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      marketing_consent_events: {
        Row: {
          channel: string;
          consent: boolean | null;
          contact: string | null;
          id: number;
          recorded_at: string;
          recorded_by: string | null;
          source: string;
          subject_id: string;
        };
        ComputedFields: never;
        Insert: {
          channel: string;
          consent?: boolean | null;
          contact?: string | null;
          id?: never;
          recorded_at?: string;
          recorded_by?: string | null;
          source: string;
          subject_id: string;
        };
        Update: {
          channel?: string;
          consent?: boolean | null;
          contact?: string | null;
          id?: never;
          recorded_at?: string;
          recorded_by?: string | null;
          source?: string;
          subject_id?: string;
        };
        Relationships: [];
      };
      online_order_events: {
        Row: {
          created_at: string;
          created_by: string | null;
          event: string;
          id: string;
          order_id: string;
          public_message: string | null;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          event: string;
          id?: string;
          order_id: string;
          public_message?: string | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          event?: string;
          id?: string;
          order_id?: string;
          public_message?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "online_order_events_order_id_fkey";
            columns: ["order_id"];
            isOneToOne: false;
            referencedRelation: "online_orders";
            referencedColumns: ["id"];
          },
        ];
      };
      online_order_lines: {
        Row: {
          color: string | null;
          description: string;
          id: string;
          line_no: number;
          location_id: string;
          order_id: string;
          quantity: number;
          reservation_id: string;
          size: string | null;
          sku: string | null;
          tax: number;
          taxable: boolean;
          total: number;
          unit: string;
          unit_price: number;
          variant_id: string;
        };
        ComputedFields: never;
        Insert: {
          color?: string | null;
          description: string;
          id?: string;
          line_no: number;
          location_id: string;
          order_id: string;
          quantity: number;
          reservation_id: string;
          size?: string | null;
          sku?: string | null;
          tax: number;
          taxable: boolean;
          total: number;
          unit: string;
          unit_price: number;
          variant_id: string;
        };
        Update: {
          color?: string | null;
          description?: string;
          id?: string;
          line_no?: number;
          location_id?: string;
          order_id?: string;
          quantity?: number;
          reservation_id?: string;
          size?: string | null;
          sku?: string | null;
          tax?: number;
          taxable?: boolean;
          total?: number;
          unit?: string;
          unit_price?: number;
          variant_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "online_order_lines_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "online_order_lines_order_id_fkey";
            columns: ["order_id"];
            isOneToOne: false;
            referencedRelation: "online_orders";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "online_order_lines_reservation_id_fkey";
            columns: ["reservation_id"];
            isOneToOne: true;
            referencedRelation: "stock_reservations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "online_order_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "online_order_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      online_orders: {
        Row: {
          account_id: string;
          address: Json | null;
          branch_id: string;
          cancelled_reason: string | null;
          contact_name: string;
          courier: string | null;
          created_at: string;
          customer_id: string | null;
          delivery_fee: number;
          discount: number;
          email: string | null;
          expires_at: string | null;
          fulfilment: string;
          id: string;
          notes_customer: string | null;
          notes_staff: string | null;
          order_no: string;
          payment_method: string;
          payment_status: string;
          phone: string;
          request_id: string;
          sale_id: string | null;
          status: string;
          subtotal: number;
          tax: number;
          total: number;
          tracking_no: string | null;
          tracking_version: number;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          account_id: string;
          address?: Json | null;
          branch_id: string;
          cancelled_reason?: string | null;
          contact_name: string;
          courier?: string | null;
          created_at?: string;
          customer_id?: string | null;
          delivery_fee: number;
          discount?: number;
          email?: string | null;
          expires_at?: string | null;
          fulfilment: string;
          id?: string;
          notes_customer?: string | null;
          notes_staff?: string | null;
          order_no?: string;
          payment_method: string;
          payment_status: string;
          phone: string;
          request_id: string;
          sale_id?: string | null;
          status: string;
          subtotal: number;
          tax: number;
          total: number;
          tracking_no?: string | null;
          tracking_version?: number;
          updated_at?: string;
        };
        Update: {
          account_id?: string;
          address?: Json | null;
          branch_id?: string;
          cancelled_reason?: string | null;
          contact_name?: string;
          courier?: string | null;
          created_at?: string;
          customer_id?: string | null;
          delivery_fee?: number;
          discount?: number;
          email?: string | null;
          expires_at?: string | null;
          fulfilment?: string;
          id?: string;
          notes_customer?: string | null;
          notes_staff?: string | null;
          order_no?: string;
          payment_method?: string;
          payment_status?: string;
          phone?: string;
          request_id?: string;
          sale_id?: string | null;
          status?: string;
          subtotal?: number;
          tax?: number;
          total?: number;
          tracking_no?: string | null;
          tracking_version?: number;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "online_orders_account_id_fkey";
            columns: ["account_id"];
            isOneToOne: false;
            referencedRelation: "customer_accounts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "online_orders_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "online_orders_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "online_orders_sale_id_fkey";
            columns: ["sale_id"];
            isOneToOne: true;
            referencedRelation: "sales";
            referencedColumns: ["id"];
          },
        ];
      };
      online_payments: {
        Row: {
          amount: number;
          created_at: string;
          id: string;
          method: string;
          needs_refund: boolean;
          order_id: string;
          provider: string;
          provider_ref: string;
          raw: Json | null;
          status: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          amount: number;
          created_at?: string;
          id?: string;
          method: string;
          needs_refund?: boolean;
          order_id: string;
          provider: string;
          provider_ref: string;
          raw?: Json | null;
          status: string;
          updated_at?: string;
        };
        Update: {
          amount?: number;
          created_at?: string;
          id?: string;
          method?: string;
          needs_refund?: boolean;
          order_id?: string;
          provider?: string;
          provider_ref?: string;
          raw?: Json | null;
          status?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "online_payments_order_id_fkey";
            columns: ["order_id"];
            isOneToOne: false;
            referencedRelation: "online_orders";
            referencedColumns: ["id"];
          },
        ];
      };
      online_return_events: {
        Row: {
          actor: string;
          created_at: string;
          created_by: string | null;
          id: string;
          message: string;
          request_id: string;
          status: string;
        };
        ComputedFields: never;
        Insert: {
          actor: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          message: string;
          request_id: string;
          status: string;
        };
        Update: {
          actor?: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          message?: string;
          request_id?: string;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: "online_return_events_request_id_fkey";
            columns: ["request_id"];
            isOneToOne: false;
            referencedRelation: "online_return_requests";
            referencedColumns: ["id"];
          },
        ];
      };
      online_return_items: {
        Row: {
          order_line_id: string;
          quantity: number;
          request_id: string;
        };
        ComputedFields: never;
        Insert: {
          order_line_id: string;
          quantity: number;
          request_id: string;
        };
        Update: {
          order_line_id?: string;
          quantity?: number;
          request_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "online_return_items_order_line_id_fkey";
            columns: ["order_line_id"];
            isOneToOne: false;
            referencedRelation: "online_order_lines";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "online_return_items_request_id_fkey";
            columns: ["request_id"];
            isOneToOne: false;
            referencedRelation: "online_return_requests";
            referencedColumns: ["id"];
          },
        ];
      };
      online_return_photos: {
        Row: {
          created_at: string;
          id: string;
          request_id: string;
          storage_path: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id: string;
          request_id: string;
          storage_path: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          request_id?: string;
          storage_path?: string;
        };
        Relationships: [
          {
            foreignKeyName: "online_return_photos_request_id_fkey";
            columns: ["request_id"];
            isOneToOne: false;
            referencedRelation: "online_return_requests";
            referencedColumns: ["id"];
          },
        ];
      };
      online_return_requests: {
        Row: {
          created_at: string;
          id: string;
          message: string;
          order_id: string;
          reason: string;
          requested_resolution: string;
          staff_note: string;
          status: string;
          updated_at: string;
          version: number;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id: string;
          message: string;
          order_id: string;
          reason: string;
          requested_resolution: string;
          staff_note?: string;
          status?: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          created_at?: string;
          id?: string;
          message?: string;
          order_id?: string;
          reason?: string;
          requested_resolution?: string;
          staff_note?: string;
          status?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: "online_return_requests_order_id_fkey";
            columns: ["order_id"];
            isOneToOne: true;
            referencedRelation: "online_orders";
            referencedColumns: ["id"];
          },
        ];
      };
      payments: {
        Row: {
          amount: number;
          bank_name: string | null;
          card_last4: string | null;
          card_type: string | null;
          cash_session_id: string | null;
          change_given: number;
          created_at: string;
          created_by: string | null;
          customer_payment_id: string | null;
          direction: string;
          holder_name: string | null;
          id: string;
          method: string;
          reference: string | null;
          return_id: string | null;
          sale_id: string | null;
          tendered: number | null;
        };
        ComputedFields: never;
        Insert: {
          amount: number;
          bank_name?: string | null;
          card_last4?: string | null;
          card_type?: string | null;
          cash_session_id?: string | null;
          change_given?: number;
          created_at?: string;
          created_by?: string | null;
          customer_payment_id?: string | null;
          direction?: string;
          holder_name?: string | null;
          id?: string;
          method: string;
          reference?: string | null;
          return_id?: string | null;
          sale_id?: string | null;
          tendered?: number | null;
        };
        Update: {
          amount?: number;
          bank_name?: string | null;
          card_last4?: string | null;
          card_type?: string | null;
          cash_session_id?: string | null;
          change_given?: number;
          created_at?: string;
          created_by?: string | null;
          customer_payment_id?: string | null;
          direction?: string;
          holder_name?: string | null;
          id?: string;
          method?: string;
          reference?: string | null;
          return_id?: string | null;
          sale_id?: string | null;
          tendered?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "payments_cash_session_id_fkey";
            columns: ["cash_session_id"];
            isOneToOne: false;
            referencedRelation: "cash_sessions";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_customer_payment_id_fkey";
            columns: ["customer_payment_id"];
            isOneToOne: false;
            referencedRelation: "customer_payments";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_return_id_fkey";
            columns: ["return_id"];
            isOneToOne: false;
            referencedRelation: "returns";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "payments_sale_id_fkey";
            columns: ["sale_id"];
            isOneToOne: false;
            referencedRelation: "sales";
            referencedColumns: ["id"];
          },
        ];
      };
      product_images: {
        Row: {
          alt: string | null;
          created_at: string;
          id: string;
          sort_order: number;
          storage_path: string;
          style_id: string;
          variant_color: string | null;
        };
        ComputedFields: never;
        Insert: {
          alt?: string | null;
          created_at?: string;
          id?: string;
          sort_order?: number;
          storage_path: string;
          style_id: string;
          variant_color?: string | null;
        };
        Update: {
          alt?: string | null;
          created_at?: string;
          id?: string;
          sort_order?: number;
          storage_path?: string;
          style_id?: string;
          variant_color?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "product_images_style_id_fkey";
            columns: ["style_id"];
            isOneToOne: false;
            referencedRelation: "product_styles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "product_images_style_id_fkey";
            columns: ["style_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["style_id"];
          },
        ];
      };
      product_styles: {
        Row: {
          active: boolean;
          brand: string | null;
          category_id: string | null;
          code: string;
          created_at: string;
          created_by: string | null;
          description: string | null;
          design_code: string | null;
          id: string;
          image_url: string | null;
          kind: string;
          lingerie: NonNullable<Json>;
          material: string | null;
          name: string;
          product_guide: NonNullable<Json>;
          published: boolean;
          season: string | null;
          size_scheme_id: string | null;
          slug: string | null;
          taxable: boolean;
          track_inventory: boolean;
          try_on: NonNullable<Json>;
          unit: string;
          updated_at: string;
          web_description: string | null;
          web_title: string | null;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          brand?: string | null;
          category_id?: string | null;
          code: string;
          created_at?: string;
          created_by?: string | null;
          description?: string | null;
          design_code?: string | null;
          id?: string;
          image_url?: string | null;
          kind: string;
          lingerie?: NonNullable<Json>;
          material?: string | null;
          name: string;
          product_guide?: NonNullable<Json>;
          published?: boolean;
          season?: string | null;
          size_scheme_id?: string | null;
          slug?: string | null;
          taxable?: boolean;
          track_inventory?: boolean;
          try_on?: NonNullable<Json>;
          unit?: string;
          updated_at?: string;
          web_description?: string | null;
          web_title?: string | null;
        };
        Update: {
          active?: boolean;
          brand?: string | null;
          category_id?: string | null;
          code?: string;
          created_at?: string;
          created_by?: string | null;
          description?: string | null;
          design_code?: string | null;
          id?: string;
          image_url?: string | null;
          kind?: string;
          lingerie?: NonNullable<Json>;
          material?: string | null;
          name?: string;
          product_guide?: NonNullable<Json>;
          published?: boolean;
          season?: string | null;
          size_scheme_id?: string | null;
          slug?: string | null;
          taxable?: boolean;
          track_inventory?: boolean;
          try_on?: NonNullable<Json>;
          unit?: string;
          updated_at?: string;
          web_description?: string | null;
          web_title?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "product_styles_category_id_fkey";
            columns: ["category_id"];
            isOneToOne: false;
            referencedRelation: "categories";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "product_styles_size_scheme_id_fkey";
            columns: ["size_scheme_id"];
            isOneToOne: false;
            referencedRelation: "size_schemes";
            referencedColumns: ["id"];
          },
        ];
      };
      product_variants: {
        Row: {
          active: boolean;
          bra_band: string | null;
          bra_cup: string | null;
          color: string | null;
          compare_at_price: number | null;
          created_at: string;
          fit: string | null;
          id: string;
          legacy_product_id: string | null;
          min_stock: number;
          price: number;
          published: boolean;
          size: string | null;
          sku: string;
          style_id: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          bra_band?: string | null;
          bra_cup?: string | null;
          color?: string | null;
          compare_at_price?: number | null;
          created_at?: string;
          fit?: string | null;
          id?: string;
          legacy_product_id?: string | null;
          min_stock?: number;
          price: number;
          published?: boolean;
          size?: string | null;
          sku: string;
          style_id: string;
          updated_at?: string;
        };
        Update: {
          active?: boolean;
          bra_band?: string | null;
          bra_cup?: string | null;
          color?: string | null;
          compare_at_price?: number | null;
          created_at?: string;
          fit?: string | null;
          id?: string;
          legacy_product_id?: string | null;
          min_stock?: number;
          price?: number;
          published?: boolean;
          size?: string | null;
          sku?: string;
          style_id?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "product_variants_style_id_fkey";
            columns: ["style_id"];
            isOneToOne: false;
            referencedRelation: "product_styles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "product_variants_style_id_fkey";
            columns: ["style_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["style_id"];
          },
        ];
      };
      return_lines: {
        Row: {
          condition: string;
          description: string;
          id: string;
          quantity: number;
          refund_amount: number;
          restocked: boolean;
          return_id: string;
          sale_line_id: string;
          tax_amount: number;
          variant_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          condition?: string;
          description: string;
          id?: string;
          quantity: number;
          refund_amount: number;
          restocked: boolean;
          return_id: string;
          sale_line_id: string;
          tax_amount?: number;
          variant_id?: string | null;
        };
        Update: {
          condition?: string;
          description?: string;
          id?: string;
          quantity?: number;
          refund_amount?: number;
          restocked?: boolean;
          return_id?: string;
          sale_line_id?: string;
          tax_amount?: number;
          variant_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "return_lines_return_id_fkey";
            columns: ["return_id"];
            isOneToOne: false;
            referencedRelation: "returns";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "return_lines_sale_line_id_fkey";
            columns: ["sale_line_id"];
            isOneToOne: false;
            referencedRelation: "sale_lines";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "return_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "return_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      returns: {
        Row: {
          branch_id: string;
          created_at: string;
          created_by: string | null;
          customer_id: string | null;
          exchange_sale_id: string | null;
          id: string;
          location_id: string;
          reason: string;
          refund_method: string;
          refund_total: number;
          request_id: string | null;
          return_no: string;
          sale_id: string;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          created_at?: string;
          created_by?: string | null;
          customer_id?: string | null;
          exchange_sale_id?: string | null;
          id?: string;
          location_id: string;
          reason: string;
          refund_method: string;
          refund_total: number;
          request_id?: string | null;
          return_no: string;
          sale_id: string;
        };
        Update: {
          branch_id?: string;
          created_at?: string;
          created_by?: string | null;
          customer_id?: string | null;
          exchange_sale_id?: string | null;
          id?: string;
          location_id?: string;
          reason?: string;
          refund_method?: string;
          refund_total?: number;
          request_id?: string | null;
          return_no?: string;
          sale_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "returns_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "returns_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "returns_exchange_sale_id_fkey";
            columns: ["exchange_sale_id"];
            isOneToOne: false;
            referencedRelation: "sales";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "returns_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "returns_sale_id_fkey";
            columns: ["sale_id"];
            isOneToOne: false;
            referencedRelation: "sales";
            referencedColumns: ["id"];
          },
        ];
      };
      sale_commissions: {
        Row: {
          basis: number;
          branch_id: string;
          created_at: string;
          kind: string | null;
          original_amount: number;
          person_name: string | null;
          rate: number;
          sale_id: string;
          user_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          basis: number;
          branch_id: string;
          created_at?: string;
          kind?: string | null;
          original_amount: number;
          person_name?: string | null;
          rate?: number;
          sale_id: string;
          user_id?: string | null;
        };
        Update: {
          basis?: number;
          branch_id?: string;
          created_at?: string;
          kind?: string | null;
          original_amount?: number;
          person_name?: string | null;
          rate?: number;
          sale_id?: string;
          user_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "sale_commissions_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sale_commissions_sale_id_fkey";
            columns: ["sale_id"];
            isOneToOne: true;
            referencedRelation: "sales";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sale_commissions_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      sale_lines: {
        Row: {
          description: string;
          gross: number;
          id: string;
          is_gift: boolean;
          line_no: number;
          manual_discount: number;
          net: number;
          promotion_discount: number;
          promotion_id: string | null;
          quantity: number;
          sale_id: string;
          sku: string | null;
          tax: number;
          taxable: boolean;
          total: number;
          unit: string;
          unit_cost: number | null;
          unit_price: number;
          variant_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          description: string;
          gross: number;
          id?: string;
          is_gift?: boolean;
          line_no: number;
          manual_discount?: number;
          net: number;
          promotion_discount?: number;
          promotion_id?: string | null;
          quantity: number;
          sale_id: string;
          sku?: string | null;
          tax?: number;
          taxable: boolean;
          total: number;
          unit: string;
          unit_cost?: number | null;
          unit_price: number;
          variant_id?: string | null;
        };
        Update: {
          description?: string;
          gross?: number;
          id?: string;
          is_gift?: boolean;
          line_no?: number;
          manual_discount?: number;
          net?: number;
          promotion_discount?: number;
          promotion_id?: string | null;
          quantity?: number;
          sale_id?: string;
          sku?: string | null;
          tax?: number;
          taxable?: boolean;
          total?: number;
          unit?: string;
          unit_cost?: number | null;
          unit_price?: number;
          variant_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "sale_lines_sale_id_fkey";
            columns: ["sale_id"];
            isOneToOne: false;
            referencedRelation: "sales";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sale_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sale_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      sales: {
        Row: {
          applied_discounts: Json | null;
          branch_id: string | null;
          card_details: Json | null;
          cashier: string | null;
          cashier_id: string | null;
          cashier_role: string | null;
          change_due: number;
          channel: string;
          created_at: string;
          customer_id: string | null;
          customer_name: string | null;
          discount_amount: number | null;
          free_gifts: Json | null;
          id: string;
          invoice_number: string;
          items: NonNullable<Json>;
          location_id: string | null;
          notes: string | null;
          payment_method: string | null;
          receipt_number: string | null;
          request_id: string | null;
          status: string | null;
          subtotal: number;
          tax_amount: number | null;
          total: number;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          applied_discounts?: Json | null;
          branch_id?: string | null;
          card_details?: Json | null;
          cashier?: string | null;
          cashier_id?: string | null;
          cashier_role?: string | null;
          change_due?: number;
          channel?: string;
          created_at?: string;
          customer_id?: string | null;
          customer_name?: string | null;
          discount_amount?: number | null;
          free_gifts?: Json | null;
          id?: string;
          invoice_number: string;
          items?: NonNullable<Json>;
          location_id?: string | null;
          notes?: string | null;
          payment_method?: string | null;
          receipt_number?: string | null;
          request_id?: string | null;
          status?: string | null;
          subtotal?: number;
          tax_amount?: number | null;
          total: number;
          updated_at?: string;
        };
        Update: {
          applied_discounts?: Json | null;
          branch_id?: string | null;
          card_details?: Json | null;
          cashier?: string | null;
          cashier_id?: string | null;
          cashier_role?: string | null;
          change_due?: number;
          channel?: string;
          created_at?: string;
          customer_id?: string | null;
          customer_name?: string | null;
          discount_amount?: number | null;
          free_gifts?: Json | null;
          id?: string;
          invoice_number?: string;
          items?: NonNullable<Json>;
          location_id?: string | null;
          notes?: string | null;
          payment_method?: string | null;
          receipt_number?: string | null;
          request_id?: string | null;
          status?: string | null;
          subtotal?: number;
          tax_amount?: number | null;
          total?: number;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "sales_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sales_cashier_id_fkey";
            columns: ["cashier_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sales_customer_id_fkey";
            columns: ["customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sales_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      sales_tabs: {
        Row: {
          cart: Json | null;
          created_at: string;
          id: string;
          name: string;
          selected_customer_id: string | null;
          updated_at: string;
          user_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          cart?: Json | null;
          created_at?: string;
          id?: string;
          name: string;
          selected_customer_id?: string | null;
          updated_at?: string;
          user_id?: string | null;
        };
        Update: {
          cart?: Json | null;
          created_at?: string;
          id?: string;
          name?: string;
          selected_customer_id?: string | null;
          updated_at?: string;
          user_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "sales_tabs_selected_customer_id_fkey";
            columns: ["selected_customer_id"];
            isOneToOne: false;
            referencedRelation: "customers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sales_tabs_user_id_fkey";
            columns: ["user_id"];
            isOneToOne: false;
            referencedRelation: "users";
            referencedColumns: ["id"];
          },
        ];
      };
      settings_history: {
        Row: {
          changed_at: string;
          changed_by: string | null;
          id: number;
          new: NonNullable<Json>;
          old: NonNullable<Json>;
        };
        ComputedFields: never;
        Insert: {
          changed_at?: string;
          changed_by?: string | null;
          id?: never;
          new: NonNullable<Json>;
          old: NonNullable<Json>;
        };
        Update: {
          changed_at?: string;
          changed_by?: string | null;
          id?: never;
          new?: NonNullable<Json>;
          old?: NonNullable<Json>;
        };
        Relationships: [];
      };
      size_schemes: {
        Row: {
          active: boolean;
          code: string;
          created_at: string;
          id: string;
          name: string;
          size_chart: Json | null;
          sizes: string[];
        };
        ComputedFields: never;
        Insert: {
          active?: boolean;
          code: string;
          created_at?: string;
          id?: string;
          name: string;
          size_chart?: Json | null;
          sizes: string[];
        };
        Update: {
          active?: boolean;
          code?: string;
          created_at?: string;
          id?: string;
          name?: string;
          size_chart?: Json | null;
          sizes?: string[];
        };
        Relationships: [];
      };
      stock_balances: {
        Row: {
          branch_id: string;
          location_id: string;
          on_hand: number;
          reserved: number;
          updated_at: string;
          variant_id: string;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          location_id: string;
          on_hand?: number;
          reserved?: number;
          updated_at?: string;
          variant_id: string;
        };
        Update: {
          branch_id?: string;
          location_id?: string;
          on_hand?: number;
          reserved?: number;
          updated_at?: string;
          variant_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "stock_balances_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_balances_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_balances_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_balances_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      stock_count_lines: {
        Row: {
          count_id: string;
          counted: number;
          counted_at: string;
          counted_by: string | null;
          difference: number | null;
          expected: number;
          id: string;
          variant_id: string;
        };
        ComputedFields: never;
        Insert: {
          count_id: string;
          counted: number;
          counted_at?: string;
          counted_by?: string | null;
          difference?: number | null;
          expected: number;
          id?: string;
          variant_id: string;
        };
        Update: {
          count_id?: string;
          counted?: number;
          counted_at?: string;
          counted_by?: string | null;
          difference?: number | null;
          expected?: number;
          id?: string;
          variant_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "stock_count_lines_count_id_fkey";
            columns: ["count_id"];
            isOneToOne: false;
            referencedRelation: "stock_counts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_count_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_count_lines_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      stock_counts: {
        Row: {
          branch_id: string;
          closed_at: string | null;
          closed_by: string | null;
          count_no: string;
          created_at: string;
          created_by: string | null;
          id: string;
          location_id: string;
          notes: string | null;
          status: string;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          closed_at?: string | null;
          closed_by?: string | null;
          count_no: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          location_id: string;
          notes?: string | null;
          status?: string;
        };
        Update: {
          branch_id?: string;
          closed_at?: string | null;
          closed_by?: string | null;
          count_no?: string;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          location_id?: string;
          notes?: string | null;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: "stock_counts_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_counts_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      stock_movements: {
        Row: {
          branch_id: string;
          channel: string;
          created_at: string;
          created_by: string | null;
          id: number;
          location_id: string;
          movement_type: string;
          quantity: number;
          reason: string | null;
          reference_id: string | null;
          reference_type: string | null;
          unit_cost: number | null;
          variant_id: string;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          channel?: string;
          created_at?: string;
          created_by?: string | null;
          id?: never;
          location_id: string;
          movement_type: string;
          quantity: number;
          reason?: string | null;
          reference_id?: string | null;
          reference_type?: string | null;
          unit_cost?: number | null;
          variant_id: string;
        };
        Update: {
          branch_id?: string;
          channel?: string;
          created_at?: string;
          created_by?: string | null;
          id?: never;
          location_id?: string;
          movement_type?: string;
          quantity?: number;
          reason?: string | null;
          reference_id?: string | null;
          reference_type?: string | null;
          unit_cost?: number | null;
          variant_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "stock_movements_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_movements_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_movements_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_movements_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      stock_reservations: {
        Row: {
          branch_id: string;
          channel: string;
          closed_at: string | null;
          created_at: string;
          created_by: string | null;
          expires_at: string | null;
          id: string;
          location_id: string;
          quantity: number;
          reference_id: string | null;
          reference_type: string | null;
          status: string;
          variant_id: string;
        };
        ComputedFields: never;
        Insert: {
          branch_id: string;
          channel: string;
          closed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          expires_at?: string | null;
          id?: string;
          location_id: string;
          quantity: number;
          reference_id?: string | null;
          reference_type?: string | null;
          status?: string;
          variant_id: string;
        };
        Update: {
          branch_id?: string;
          channel?: string;
          closed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          expires_at?: string | null;
          id?: string;
          location_id?: string;
          quantity?: number;
          reference_id?: string | null;
          reference_type?: string | null;
          status?: string;
          variant_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "stock_reservations_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_reservations_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_reservations_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_reservations_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
      suppliers: {
        Row: {
          address: string | null;
          created_at: string;
          email: string | null;
          id: string;
          name: string;
          payment_terms: string | null;
          phone: string | null;
          rating: number | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          address?: string | null;
          created_at?: string;
          email?: string | null;
          id?: string;
          name: string;
          payment_terms?: string | null;
          phone?: string | null;
          rating?: number | null;
          updated_at?: string;
        };
        Update: {
          address?: string | null;
          created_at?: string;
          email?: string | null;
          id?: string;
          name?: string;
          payment_terms?: string | null;
          phone?: string | null;
          rating?: number | null;
          updated_at?: string;
        };
        Relationships: [];
      };
      users: {
        Row: {
          active: boolean | null;
          avatar: string | null;
          created_at: string;
          email: string;
          id: string;
          last_login: string | null;
          name: string;
          permissions: string[] | null;
          role: string;
          updated_at: string;
          username: string;
        };
        ComputedFields: never;
        Insert: {
          active?: boolean | null;
          avatar?: string | null;
          created_at?: string;
          email: string;
          id: string;
          last_login?: string | null;
          name: string;
          permissions?: string[] | null;
          role?: string;
          updated_at?: string;
          username: string;
        };
        Update: {
          active?: boolean | null;
          avatar?: string | null;
          created_at?: string;
          email?: string;
          id?: string;
          last_login?: string | null;
          name?: string;
          permissions?: string[] | null;
          role?: string;
          updated_at?: string;
          username?: string;
        };
        Relationships: [];
      };
      variant_costs: {
        Row: {
          unit_cost: number;
          updated_at: string;
          variant_id: string;
        };
        ComputedFields: never;
        Insert: {
          unit_cost?: number;
          updated_at?: string;
          variant_id: string;
        };
        Update: {
          unit_cost?: number;
          updated_at?: string;
          variant_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "variant_costs_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: true;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "variant_costs_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: true;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
    };
    Views: {
      public_catalog: {
        Row: {
          brand: string | null;
          category: string | null;
          color: string | null;
          compare_at_price: number | null;
          description: string | null;
          fit: string | null;
          kind: string | null;
          material: string | null;
          price: number | null;
          season: string | null;
          size: string | null;
          sku: string | null;
          slug: string | null;
          stock_level: string | null;
          style_id: string | null;
          title: string | null;
          unit: string | null;
          variant_id: string | null;
        };
        ComputedFields: never;
        Relationships: [];
      };
      variant_stock: {
        Row: {
          available: number | null;
          branch_id: string | null;
          location_id: string | null;
          on_hand: number | null;
          reserved: number | null;
          variant_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          available?: never;
          branch_id?: string | null;
          location_id?: string | null;
          on_hand?: number | null;
          reserved?: number | null;
          variant_id?: string | null;
        };
        Update: {
          available?: never;
          branch_id?: string | null;
          location_id?: string | null;
          on_hand?: number | null;
          reserved?: number | null;
          variant_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "stock_balances_branch_id_fkey";
            columns: ["branch_id"];
            isOneToOne: false;
            referencedRelation: "branches";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_balances_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_balances_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "product_variants";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_balances_variant_id_fkey";
            columns: ["variant_id"];
            isOneToOne: false;
            referencedRelation: "public_catalog";
            referencedColumns: ["variant_id"];
          },
        ];
      };
    };
    Functions: {
      adjust_customer_balance: {
        Args: {
          p_amount: number;
          p_customer: string;
          p_reason: string;
          p_request_id: string;
        };
        Returns: Json;
      };
      adjust_stock: {
        Args: {
          p_location_id: string;
          p_movement_type?: string;
          p_quantity: number;
          p_reason: string;
          p_request_id?: string;
          p_variant_id: string;
        };
        Returns: Json;
      };
      advance_online_order: { Args: { p: Json }; Returns: Json };
      approve_stock_count: { Args: { p_count_id: string }; Returns: Json };
      backfill_customer_ledger: {
        Args: Record<PropertyKey, never>;
        Returns: undefined;
      };
      cancel_my_online_order: { Args: { p_order_no: string }; Returns: Json };
      cancel_online_order: { Args: { p: Json }; Returns: Json };
      cancel_online_order_internal: {
        Args: { p_id: string; p_reason: string };
        Returns: Json;
      };
      cancel_stock_count: {
        Args: { p_count_id: string };
        Returns: {
          branch_id: string;
          closed_at: string | null;
          closed_by: string | null;
          count_no: string;
          created_at: string;
          created_by: string | null;
          id: string;
          location_id: string;
          notes: string | null;
          status: string;
        };
        SetofOptions: {
          from: "*";
          to: "stock_counts";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      cash_session_detail: { Args: { p_session_id: string }; Returns: Json };
      cash_session_summary: { Args: { p_session_id: string }; Returns: Json };
      catalog_collections: {
        Args: Record<PropertyKey, never>;
        Returns: {
          description: string;
          hero_image_path: string;
          name: string;
          slug: string;
        }[];
      };
      catalog_facets: { Args: { p_collection: string }; Returns: Json };
      catalog_list: {
        Args: { p: Json };
        Returns: {
          angle_paths: string[];
          colors: string[];
          compare_at_price: number;
          image_path: string;
          max_price: number;
          min_price: number;
          sizes: string[];
          slug: string;
          stock_level: string;
          style_id: string;
          title: string;
          total_count: number;
        }[];
      };
      catalog_policy: { Args: Record<PropertyKey, never>; Returns: Json };
      catalog_product: { Args: { p_slug: string }; Returns: Json };
      catalog_style_rows: {
        Args: Record<PropertyKey, never>;
        Returns: {
          colors: string[];
          compare_at_price: number;
          created_at: string;
          image_path: string;
          max_price: number;
          min_price: number;
          sizes: string[];
          slug: string;
          stock_level: string;
          style_id: string;
          title: string;
        }[];
      };
      close_cash_session: {
        Args: { p_counted_cash: number; p_notes?: string };
        Returns: Json;
      };
      close_cash_session_internal: {
        Args: {
          p_closed_by: string;
          p_counted: number;
          p_notes: string;
          p_session_id: string;
        };
        Returns: Json;
      };
      close_online_reservations: {
        Args: { p_order: string; p_status: string };
        Returns: undefined;
      };
      close_reservation: {
        Args: { p_reservation_id: string; p_status: string };
        Returns: {
          branch_id: string;
          channel: string;
          closed_at: string | null;
          created_at: string;
          created_by: string | null;
          expires_at: string | null;
          id: string;
          location_id: string;
          quantity: number;
          reference_id: string | null;
          reference_type: string | null;
          status: string;
          variant_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "stock_reservations";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      collect_cod_payment: { Args: { p: Json }; Returns: Json };
      commission_branches: { Args: Record<PropertyKey, never>; Returns: Json };
      commission_overview: { Args: { p: Json }; Returns: Json };
      commission_sellers: { Args: { p_branch: string }; Returns: Json };
      create_online_order: { Args: { p: Json }; Returns: Json };
      create_return: {
        Args: { p: Json; p_refund_method: string };
        Returns: {
          branch_id: string;
          created_at: string;
          created_by: string | null;
          customer_id: string | null;
          exchange_sale_id: string | null;
          id: string;
          location_id: string;
          reason: string;
          refund_method: string;
          refund_total: number;
          request_id: string | null;
          return_no: string;
          sale_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "returns";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      create_return_request: { Args: { p: Json }; Returns: Json };
      current_app_role: { Args: Record<PropertyKey, never>; Returns: string };
      current_cash_session: { Args: Record<PropertyKey, never>; Returns: Json };
      customer_discount_codes: {
        Args: { p_customer_id: string };
        Returns: Json;
      };
      customer_statement: {
        Args: { p_customer: string; p_from: string; p_to: string };
        Returns: Json;
      };
      customers_with_balance: {
        Args: { p?: Json };
        Returns: {
          customer: Json;
          last_payment_date: string;
          oldest_unpaid_date: string;
          total_count: number;
        }[];
      };
      default_branch_id: { Args: Record<PropertyKey, never>; Returns: string };
      delete_business_lookup: {
        Args: { p_id: string; p_kind: string };
        Returns: undefined;
      };
      discount_code_json: {
        Args: {
          p_code: Omit<
            Database["public"]["Tables"]["discount_codes"]["Row"],
            Database["public"]["Tables"]["discount_codes"]["ComputedFields"]
          >;
        };
        Returns: Json;
      };
      expire_online_orders: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      expire_stock_reservations: {
        Args: Record<PropertyKey, never>;
        Returns: number;
      };
      find_sale_for_return: { Args: { p_invoice: string }; Returns: Json };
      force_close_cash_session: {
        Args: {
          p_counted_cash: number;
          p_notes: string;
          p_request_id: string;
          p_session_id: string;
        };
        Returns: Json;
      };
      generate_invoice_number: {
        Args: Record<PropertyKey, never>;
        Returns: string;
      };
      has_app_role: { Args: { roles: string[] }; Returns: boolean };
      idempotency_begin: {
        Args: { p_key: string; p_operation: string };
        Returns: Json;
      };
      idempotency_finish: {
        Args: { p_key: string; p_result: Json };
        Returns: Json;
      };
      import_opening_balances: { Args: { p: Json }; Returns: Json };
      initiate_online_payment: {
        Args: {
          p_account_id: string;
          p_method: string;
          p_order_no: string;
          p_provider: string;
          p_provider_ref: string;
        };
        Returns: Json;
      };
      is_branch_member: { Args: { p_branch_id: string }; Returns: boolean };
      is_counter_staff: { Args: Record<PropertyKey, never>; Returns: boolean };
      is_staff: { Args: Record<PropertyKey, never>; Returns: boolean };
      is_website_customer: {
        Args: Record<PropertyKey, never>;
        Returns: boolean;
      };
      issue_customer_welcome_code: {
        Args: { p_customer_id: string };
        Returns: Json;
      };
      issue_welcome_code: {
        Args: { p_customer_id: string };
        Returns: {
          active: boolean;
          code: string;
          created_at: string;
          created_by: string | null;
          customer_id: string | null;
          description: string | null;
          discount_type: string;
          expires_at: string | null;
          id: string;
          kind: string;
          max_discount: number | null;
          max_uses: number | null;
          min_amount: number | null;
          updated_at: string;
          used_count: number;
          valid_from: string;
          value: number;
        };
        SetofOptions: {
          from: "*";
          to: "discount_codes";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      link_customer_account: {
        Args: Record<PropertyKey, never>;
        Returns: Json;
      };
      list_business_lookups: { Args: { p_kind: string }; Returns: Json };
      list_cash_sessions: {
        Args: { p?: Json };
        Returns: {
          cash_in: number;
          cash_out: number;
          cash_sales: number;
          closed_at: string;
          closed_by_name: string;
          closing_notes: string;
          counted_cash: number;
          expected_cash: number;
          id: string;
          opened_at: string;
          opening_float: number;
          over_limit: boolean;
          refunds: number;
          session_no: string;
          status: string;
          total_count: number;
          user_id: string;
          user_name: string;
          variance: number;
        }[];
      };
      list_online_orders: { Args: { p?: Json }; Returns: Json };
      list_return_requests: { Args: { p?: Json }; Returns: Json };
      lock_stock_balance: {
        Args: { p_location_id: string; p_variant_id: string };
        Returns: {
          branch_id: string;
          location_id: string;
          on_hand: number;
          reserved: number;
          updated_at: string;
          variant_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "stock_balances";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      lookup_usage: { Args: { p_id: string; p_kind: string }; Returns: number };
      mark_online_order_paid: {
        Args: {
          p_amount: number;
          p_method: string;
          p_order_no: string;
          p_provider: string;
          p_provider_ref: string;
          p_raw: Json;
        };
        Returns: Json;
      };
      marketing_audience: {
        Args: {
          p_channel: string;
          p_limit?: number;
          p_offset?: number;
          p_query?: string;
        };
        Returns: {
          consent_at: string;
          contact: string;
          name: string;
          source: string;
          total_count: number;
        }[];
      };
      my_online_order: { Args: { p_order_no: string }; Returns: Json };
      my_online_orders: { Args: Record<PropertyKey, never>; Returns: Json };
      my_return_request: { Args: { p_order_no: string }; Returns: Json };
      needs_bootstrap: { Args: Record<PropertyKey, never>; Returns: boolean };
      new_discount_code: { Args: Record<PropertyKey, never>; Returns: string };
      normalize_discount_code: { Args: { p_code: string }; Returns: string };
      normalize_phone: { Args: { p_phone: string }; Returns: string };
      online_order_detail: { Args: { p_id: string }; Returns: Json };
      online_order_public: { Args: { p_id: string }; Returns: Json };
      open_cash_session: {
        Args: { p_location_id?: string; p_opening_float: number };
        Returns: Json;
      };
      post_customer_payment: { Args: { p: Json }; Returns: Json };
      post_exchange: { Args: { p: Json }; Returns: Json };
      post_exchange_without_commission: { Args: { p: Json }; Returns: Json };
      post_goods_receipt: { Args: { p: Json }; Returns: Json };
      post_return: { Args: { p: Json }; Returns: Json };
      post_sale: { Args: { p_request: Json }; Returns: Json };
      post_sale_without_commission: {
        Args: { p_request: Json };
        Returns: Json;
      };
      post_stock_movement: {
        Args: {
          p_channel?: string;
          p_location_id: string;
          p_movement_type: string;
          p_quantity: number;
          p_reason?: string;
          p_reference_id?: string;
          p_reference_type?: string;
          p_unit_cost?: number;
          p_variant_id: string;
        };
        Returns: {
          branch_id: string;
          location_id: string;
          on_hand: number;
          reserved: number;
          updated_at: string;
          variant_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "stock_balances";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      prepare_return_photo: {
        Args: { p_id: string; p_photo_id: string };
        Returns: Json;
      };
      promotion_item_matches: {
        Args: { p_ref: string; p_variant_id: string };
        Returns: boolean;
      };
      publish_style: {
        Args: { p_dry_run?: boolean; p_published: boolean; p_style: string };
        Returns: Json;
      };
      quote_online_order: { Args: { p: Json }; Returns: Json };
      quote_sale: { Args: { p_request: Json }; Returns: Json };
      receive_cod_parcel_return: { Args: { p: Json }; Returns: Json };
      record_cash_movement: {
        Args: { p_amount: number; p_reason: string };
        Returns: Json;
      };
      record_commission_payout: {
        Args: {
          p_amount: number;
          p_branch: string;
          p_note: string;
          p_request: string;
          p_user: string;
        };
        Returns: Json;
      };
      record_online_payment_event: {
        Args: {
          p_amount: number;
          p_method: string;
          p_order_no: string;
          p_provider: string;
          p_provider_ref: string;
          p_raw: Json;
          p_status: string;
        };
        Returns: Json;
      };
      record_online_refund: { Args: { p: Json }; Returns: Json };
      record_stock_count: {
        Args: { p_count_id: string; p_counted: number; p_variant_id: string };
        Returns: {
          count_id: string;
          counted: number;
          counted_at: string;
          counted_by: string | null;
          difference: number | null;
          expected: number;
          id: string;
          variant_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "stock_count_lines";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      release_reservation: {
        Args: { p_reservation_id: string };
        Returns: {
          branch_id: string;
          channel: string;
          closed_at: string | null;
          created_at: string;
          created_by: string | null;
          expires_at: string | null;
          id: string;
          location_id: string;
          quantity: number;
          reference_id: string | null;
          reference_type: string | null;
          status: string;
          variant_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "stock_reservations";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      reply_return_request: { Args: { p: Json }; Returns: Json };
      report_line_activity: {
        Args: { p_branch: string; p_from: string; p_to: string };
        Returns: {
          cost: number;
          discounts: number;
          is_return: boolean;
          net: number;
          quantity: number;
          returns: number;
          sale_id: string;
          variant_id: string;
        }[];
      };
      report_sales_summary: {
        Args: { p_branch?: string; p_from: string; p_to: string };
        Returns: {
          cost: number;
          day: string;
          discounts: number;
          gross: number;
          invoices: number;
          margin: number;
          net_after_returns: number;
          net_sales: number;
          returns: number;
          returns_tax: number;
          tax: number;
        }[];
      };
      report_size_color_matrix: {
        Args: {
          p_branch?: string;
          p_from: string;
          p_style?: string;
          p_to: string;
        };
        Returns: {
          color: string;
          on_hand: number;
          size: string;
          sold: number;
        }[];
      };
      report_staff_sales: {
        Args: { p_branch?: string; p_from: string; p_to: string };
        Returns: {
          discounts: number;
          invoices: number;
          name: string;
          net_sales: number;
          returns: number;
          user_id: string;
        }[];
      };
      report_tenders: {
        Args: { p_branch?: string; p_from: string; p_to: string };
        Returns: {
          count: number;
          method: string;
          money_in: number;
          money_out: number;
          net: number;
        }[];
      };
      report_top_items: {
        Args: {
          p_branch?: string;
          p_from: string;
          p_group?: string;
          p_limit?: number;
          p_to: string;
        };
        Returns: {
          cost: number;
          key: string;
          label: string;
          margin: number;
          net: number;
          quantity: number;
        }[];
      };
      report_tz: { Args: Record<PropertyKey, never>; Returns: string };
      request_begin: {
        Args: { p_key: string; p_operation: string };
        Returns: Json;
      };
      require_online_service: {
        Args: Record<PropertyKey, never>;
        Returns: undefined;
      };
      require_website_customer: {
        Args: Record<PropertyKey, never>;
        Returns: string;
      };
      reserve_stock: {
        Args: {
          p_channel: string;
          p_expires_at?: string;
          p_location_id: string;
          p_quantity: number;
          p_reference_id?: string;
          p_reference_type?: string;
          p_variant_id: string;
        };
        Returns: {
          branch_id: string;
          channel: string;
          closed_at: string | null;
          created_at: string;
          created_by: string | null;
          expires_at: string | null;
          id: string;
          location_id: string;
          quantity: number;
          reference_id: string | null;
          reference_type: string | null;
          status: string;
          variant_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "stock_reservations";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      review_return_request: { Args: { p: Json }; Returns: Json };
      sale_detail: { Args: { p_sale_id: string }; Returns: Json };
      sale_returnable: { Args: { p_sale_id: string }; Returns: Json };
      sanitize_card_details: { Args: { details: Json }; Returns: Json };
      save_business_lookup: { Args: { p: Json }; Returns: string };
      save_collection: { Args: { p: Json }; Returns: Json };
      save_commission_rule: {
        Args: {
          p_branch: string;
          p_enabled: boolean;
          p_kind: string;
          p_rate: number;
          p_user: string;
        };
        Returns: undefined;
      };
      save_discount_code: { Args: { p: Json }; Returns: Json };
      save_discount_code_settings: { Args: { p: Json }; Returns: Json };
      save_product_images: {
        Args: { p_images: Json; p_request_id: string; p_style: string };
        Returns: Json;
      };
      save_style: { Args: { p: Json }; Returns: string };
      save_style_base: { Args: { p: Json }; Returns: string };
      save_style_web_details: {
        Args: { p: Json; p_request_id: string; p_style: string };
        Returns: Json;
      };
      search_sales: {
        Args: { p?: Json };
        Returns: {
          cashier_name: string;
          created_at: string;
          customer_id: string;
          customer_name: string;
          id: string;
          invoice_number: string;
          line_count: number;
          paid_methods: string[];
          returned_amount: number;
          status: string;
          total: number;
          total_count: number;
        }[];
      };
      search_variants: {
        Args: { p?: Json };
        Returns: {
          active: boolean;
          available: number;
          barcode: string;
          barcodes: string[];
          category: string;
          color: string;
          created_at: string;
          description: string;
          fit: string;
          image: string;
          kind: string;
          min_stock: number;
          name: string;
          on_hand: number;
          price: number;
          size: string;
          sku: string;
          style_id: string;
          taxable: boolean;
          total_count: number;
          track_inventory: boolean;
          unit: string;
          updated_at: string;
          variant_id: string;
        }[];
      };
      set_collection_styles: {
        Args: {
          p_collection: string;
          p_request_id: string;
          p_style_ids: string[];
        };
        Returns: Json;
      };
      staff_link_customer_account: {
        Args: { p_account: string; p_customer: string; p_request_id: string };
        Returns: Json;
      };
      staff_return_request: { Args: { p_order_id: string }; Returns: Json };
      start_stock_count: {
        Args: { p_location_id?: string; p_notes?: string };
        Returns: {
          branch_id: string;
          closed_at: string | null;
          closed_by: string | null;
          count_no: string;
          created_at: string;
          created_by: string | null;
          id: string;
          location_id: string;
          notes: string | null;
          status: string;
        };
        SetofOptions: {
          from: "*";
          to: "stock_counts";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      update_online_tracking: { Args: { p: Json }; Returns: Json };
      update_settings: { Args: { p: Json }; Returns: Json };
      variant_by_code: {
        Args: { p_code: string; p_location?: string };
        Returns: {
          active: boolean;
          available: number;
          barcode: string;
          barcodes: string[];
          category: string;
          color: string;
          created_at: string;
          description: string;
          fit: string;
          image: string;
          kind: string;
          min_stock: number;
          name: string;
          on_hand: number;
          price: number;
          size: string;
          sku: string;
          style_id: string;
          taxable: boolean;
          total_count: number;
          track_inventory: boolean;
          unit: string;
          updated_at: string;
          variant_id: string;
        }[];
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<
  keyof Database,
  "public"
>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {},
  },
} as const;
