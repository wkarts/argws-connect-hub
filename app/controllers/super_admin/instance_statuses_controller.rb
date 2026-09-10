class SuperAdmin::InstanceStatusesController < SuperAdmin::ApplicationController
  def show
    @metrics = {}
    hub_version
    sha
    postgres_status
    redis_metrics
    hub_edition
    instance_meta
  end

  def hub_edition
    @metrics['Edição do HUB'] = if HubApp.enterprise?
                                  'Enterprise'
                                elsif HubApp.custom?
                                  'Personalizada'
                                else
                                  'Community'
                                end
  end

  def instance_meta
    @metrics['Migrações do banco de dados'] = ActiveRecord::Base.connection.migration_context.needs_migration? ? 'pendentes' : 'concluídas'
  end

  def hub_version
    @metrics['Versão do HUB'] = Hub.version
  end

  def sha
    @metrics['Git SHA'] = GIT_HASH
  end

  def postgres_status
    @metrics['PostgreSQL disponível'] = ActiveRecord::Base.connection.active? ? 'sim' : 'não'
  end

  def redis_metrics
    r = Redis.new(Redis::Config.app)
    if r.ping == 'PONG'
      redis_server = r.info
      @metrics['Redis disponível'] = 'sim'
      @metrics['Versão do Redis'] = redis_server['redis_version']
      @metrics['Clientes conectados ao Redis'] = redis_server['connected_clients']
      @metrics['Limite de clientes do Redis (maxclients)'] = redis_server['maxclients']
      @metrics['Memória usada pelo Redis'] = redis_server['used_memory_human']
      @metrics['Pico de memória do Redis'] = redis_server['used_memory_peak_human']
      @metrics['Memória total disponível ao Redis'] = redis_server['total_system_memory_human']
      @metrics['Limite de memória do Redis (maxmemory)'] = redis_server['maxmemory']
      @metrics['Política de memória do Redis (maxmemory-policy)'] = redis_server['maxmemory_policy']
    end
  rescue Redis::CannotConnectError
    @metrics['Redis disponível'] = 'não'
  end
end
