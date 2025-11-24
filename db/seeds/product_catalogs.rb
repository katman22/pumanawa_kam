# db/seeds/product_catalogs.rb
ProductCatalog.ensure_seed!([
                              {
                                name: "Standard Monthly",
                                tier: "standard",
                                external_id_ios: "ct_standard_monthly",
                                external_id_android: "ct_standard_monthly",
                                is_addon: false,
                                feature_flags: %w[homes:2 changes:1 updates:2min],
                                status: "active"
                              },
                              {
                                name: "Standard Yearly",
                                tier: "standard",
                                external_id_ios: "ct_standard_yearly",
                                external_id_android: "ct_standard_yearly",
                                is_addon: false,
                                feature_flags: %w[homes:2 changes:1 updates:2min],
                                status: "active"
                              },
                              {
                                name: "Pro Monthly",
                                tier: "pro",
                                external_id_ios: "ct_pro_monthly",
                                external_id_android: "ct_pro_monthly",
                                is_addon: false,
                                feature_flags: %w[homes:4 changes:2 widget:1 realtime],
                                status: "active"
                              },
                              {
                                name: "Pro Yearly",
                                tier: "pro",
                                external_id_ios: "ct_pro_yearly",
                                external_id_android: "ct_pro_yearly",
                                is_addon: false,
                                feature_flags: %w[homes:4 changes:2 widget:1 realtime],
                                status: "active"
                              },
                              {
                                name: "Premium Monthly",
                                tier: "premium",
                                external_id_ios: "ct_premium_monthly",
                                external_id_android: "ct_premium_monthly",
                                is_addon: false,
                                feature_flags: %w[homes:all changes:unlimited realtime],
                                status: "active"
                              },
                              {
                                name: "Premium Yearly",
                                tier: "premium",
                                external_id_ios: "ct_premium_yearly",
                                external_id_android: "ct_premium_yearly",
                                is_addon: false,
                                feature_flags: %w[homes:all changes:unlimited realtime],
                                status: "active"
                              }
                            ])
