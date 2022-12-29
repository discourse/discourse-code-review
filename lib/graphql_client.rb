# frozen_string_literal: true

class GraphQLClient
  class GraphQLError < StandardError
  end

  class PaginatedQuery
    include Enumerable

    def initialize(client, &query)
      @client = client
      @query = query
    end

    def each(&blk)
      cursor = nil
      execute_block = client.method(:execute)

      loop do
        results, cursor, has_next_page =
          query.call(execute_block, cursor).values_at(:items, :cursor, :has_next_page)

        results.each(&blk)

        break unless has_next_page
      end
    end

    private

    attr_reader :client
    attr_reader :query
  end

  def initialize(client)
    @client = client
  end

  def execute(query)
    response = client.post("/graphql", { query: query }.to_json)
    if response[:errors]
      raise GraphQLError, response[:errors].inspect
    else
      response[:data]
    end
  end

  def paginated_query(&blk)
    PaginatedQuery.new(self, &blk)
  end

  private

  attr_reader :client
end
