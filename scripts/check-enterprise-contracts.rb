# frozen_string_literal: true

required_files = %w[
  enterprise/app/controllers/api/v1/accounts/response_sources_controller.rb
  enterprise/app/controllers/enterprise/concerns/application_controller_concern.rb
  enterprise/app/controllers/enterprise/api/v1/accounts/conversations_controller.rb
  enterprise/app/controllers/enterprise/api/v1/accounts/inboxes_controller.rb
  enterprise/app/controllers/enterprise/api/v1/accounts_controller.rb
  enterprise/app/controllers/enterprise/api/v2/accounts_controller.rb
  enterprise/app/controllers/enterprise/devise_overrides/sessions_controller.rb
  enterprise/app/controllers/enterprise/public/api/v1/portals/articles_controller.rb
  enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb
  enterprise/app/controllers/enterprise/widgets_controller.rb
  enterprise/app/controllers/super_admin/enterprise_base_controller.rb
  enterprise/app/controllers/super_admin/response_sources_controller.rb
  enterprise/app/controllers/super_admin/response_documents_controller.rb
  enterprise/app/controllers/super_admin/responses_controller.rb
  enterprise/app/dashboards/response_source_dashboard.rb
  enterprise/app/dashboards/response_document_dashboard.rb
  enterprise/app/dashboards/response_dashboard.rb
  enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb
  enterprise/app/jobs/enterprise/account/conversations_resolution_scheduler_job.rb
  enterprise/app/jobs/enterprise/delete_object_job.rb
  enterprise/app/jobs/enterprise/trigger_scheduled_items_job.rb
  enterprise/app/jobs/portal/article_indexing_job.rb
  enterprise/app/jobs/response_bot/response_bot_job.rb
  enterprise/app/jobs/response_bot/response_builder_job.rb
  enterprise/app/jobs/response_bot/response_document_content_job.rb
  enterprise/app/jobs/sla/process_account_applied_slas_job.rb
  enterprise/app/jobs/sla/process_applied_sla_job.rb
  enterprise/app/jobs/sla/trigger_slas_for_accounts_job.rb
  enterprise/app/mailers/enterprise/agent_notifications/conversation_notifications_mailer.rb
  enterprise/app/services/features/base_service.rb
  enterprise/app/services/features/response_bot_service.rb
  enterprise/app/services/features/helpcenter_embedding_search_service.rb
  enterprise/app/services/openai/embeddings_service.rb
  enterprise/app/services/page_crawler_service.rb
  enterprise/app/services/enterprise/action_service.rb
  enterprise/app/services/enterprise/clearbit_lookup_service.rb
  enterprise/app/services/enterprise/message_templates/response_bot_service.rb
  enterprise/app/services/enterprise/message_templates/hook_execution_service.rb
  enterprise/app/services/sla/evaluate_applied_sla_service.rb
  enterprise/app/views/api/v1/accounts/applied_slas/index.json.jbuilder
  enterprise/app/views/api/v1/accounts/applied_slas/metrics.json.jbuilder
  enterprise/app/views/api/v1/accounts/applied_slas/download.csv.erb
  enterprise/app/views/api/v1/accounts/sla_policies/create.json.jbuilder
  enterprise/app/views/api/v1/accounts/sla_policies/index.json.jbuilder
  enterprise/app/views/api/v1/accounts/sla_policies/show.json.jbuilder
  enterprise/app/views/api/v1/accounts/sla_policies/update.json.jbuilder
  enterprise/app/views/api/v1/models/_applied_sla.json.jbuilder
  enterprise/app/views/api/v1/models/_sla_event.json.jbuilder
  enterprise/app/views/enterprise/api/v1/accounts/partials/_account.json.jbuilder
  enterprise/app/views/enterprise/api/v1/conversations/partials/_conversation.json.jbuilder
  enterprise/app/views/super_admin/response_sources/chat.html.erb
  enterprise/app/views/super_admin/response_sources/show.html.erb
  enterprise/lib/chat_gpt.rb
]

forbidden_files = %w[
  enterprise/app/controllers/enterprise/webhooks/stripe_controller.rb
  enterprise/app/jobs/enterprise/create_stripe_customer_job.rb
  enterprise/app/services/enterprise/billing/create_session_service.rb
  enterprise/app/services/enterprise/billing/create_stripe_customer_service.rb
  enterprise/app/services/enterprise/billing/update_stripe_subscription_service.rb
]

missing = required_files.reject { |path| File.file?(path) }
forbidden = forbidden_files.select { |path| File.exist?(path) }

unless missing.empty?
  warn 'Missing required Enterprise runtime files:'
  missing.each { |path| warn " - #{path}" }
end

unless forbidden.empty?
  warn 'Legacy billing/Stripe Enterprise files must not be restored in HUB 1.x:'
  forbidden.each { |path| warn " - #{path}" }
end

exit 1 if missing.any? || forbidden.any?

puts "Enterprise runtime contracts OK: #{required_files.length} required files present"
