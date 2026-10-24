# PROTOTYPE — throwaway code. Not production. Do not merge into main.
#
# Runs the structured output approach (#20) and the tool calling approach (#26) on the same goals
# for light / standard / deep, records each generation, and prints a summary table per approach x difficulty.
#
# Usage (GEMINI_API_KEY in .env):
#   RUNS=3 ruby prototypes/compare-generation.prototype.rb
#   ruby prototypes/compare-generation.prototype.rb --dry-run
#   ruby prototypes/compare-generation.prototype.rb --table prototypes/output/compare-XXXX.json   # table only
#
# Cost is estimated from usageMetadata at gemini-3.1-flash-lite prices and 155 JPY/USD.
# Thinking tokens are billed as output. The run stops once the estimate passes BUDGET_YEN (default 900).

require_relative 'llm-tool-calling.prototype'

# 2 つの方式を比べる．
module ComparePrototype
  USD_PER_M_INPUT = 0.25
  USD_PER_M_OUTPUT = 1.50
  JPY_PER_USD = 155

  # ゴール：既存ノードを再利用させるもの（#20 と同じ），プログラミング，プログラミング以外．
  GOALS = {
    'reuse' => 'React で Todo アプリを作れるようになる',
    'programming' => 'Python で CSV のデータを集計してグラフにできるようになる',
    'non_programming' => '日商簿記 3 級に合格する'
  }.freeze

  # 難易度ごとのサブノード数の目安（メインノード 1 つあたり．basic-design 6.3）．
  SUB_RANGE = { 'standard' => 2..3, 'deep' => 3..4 }.freeze

  # 429 / 503 なら 60 秒待って同じリクエストを送り直す．待った時間は所要時間から引くために記録する．
  # 200 以外ではストリームを yield しないので，送り直しても途中まで反映した呼び出しはない．
  class RetryingClient
    attr_reader :waits # [リクエストの番号, 待った秒数]

    # 包む LLM クライアントを受け取る．
    def initialize(client)
      @client = client
      @waits = []
      @requests = 0
    end

    # 包んだクライアントの stream を呼ぶ．
    def stream(body, &block)
      index = @requests
      @requests += 1
      begin
        @client.stream(body, &block)
      rescue MapPrototype::ApiError => e
        raise unless [429, 503].include?(e.status) && @waits.size < 10

        sleep 60
        @waits << [index, 60]
        retry
      end
    end

    # index 番目までのリクエストで待った秒数の合計．
    def waited(upto = Float::INFINITY)
      @waits.sum { |i, s| i <= upto ? s : 0 }
    end
  end

  # usageMetadata の合計から費用（円）を見積もる．
  def self.yen(prompt, output)
    ((prompt * USD_PER_M_INPUT + output * USD_PER_M_OUTPUT) / 1_000_000 * JPY_PER_USD).round(2)
  end

  # 再利用の正しさを数える．どちらの方式も #20 の出力の形（main_nodes）で数える．
  # rewritten: 再利用ノードの既存サブノードを書き直した数．
  # recreated: 既存ノードと同じタイトルの新規ノード（再利用すべきだった）．
  def self.reuse_stats(main_nodes)
    existing = MapPrototype::EXISTING_NODES.to_h { |n| [n['id'], n] }
    titles = MapPrototype::EXISTING_NODES.to_set { |n| norm(n['title']) }
    stats = { 'reused' => 0, 'rewritten' => 0, 'recreated' => [] }
    walk = lambda do |nodes, parent|
      nodes.each do |n|
        if n['existing_node_id']
          stats['reused'] += 1
          stats['rewritten'] += 1 if parent && (existing.dig(parent['existing_node_id'], 'sub_node_ids') || []).include?(n['existing_node_id'])
        elsif titles.include?(norm(n['title']))
          stats['recreated'] << n['title']
        end
        walk.call(n['sub_nodes'] || [], n)
      end
    end
    walk.call(main_nodes, nil)
    stats
  end

  # サブノード数が目安に入ったメインノードの数と，メインノードの数．ライトは目安がないので nil．
  # 再利用ノードは既存サブノードも数える．ディープでは重要度 0.8 以上のメインノードに 3 階層目があることも見る．
  def self.sub_guideline(main_nodes, difficulty)
    range = SUB_RANGE[difficulty] or return nil
    existing = MapPrototype::EXISTING_NODES.to_h { |n| [n['id'], n['sub_node_ids']] }
    ok = main_nodes.count do |n|
      subs = n['sub_nodes'] || []
      ids = existing.fetch(n['existing_node_id'], []) | subs.filter_map { |s| s['existing_node_id'] }
      count = ids.size + subs.count { |s| s['existing_node_id'].nil? }
      deep_ok = difficulty != 'deep' || n['importance_score'].to_f < 0.8 || subs.any? { |s| (s['sub_nodes'] || []).any? }
      range.cover?(count) && deep_ok
    end
    [ok, main_nodes.size]
  end

  # 空白と大文字小文字の違いを無視して比べる．
  def self.norm(s)
    s.to_s.downcase.gsub(/\s+/, '')
  end

  # 両方式で共通の項目（形と再利用）．
  def self.shape(main_nodes, final_errors, difficulty)
    {
      'count_in_range' => final_errors.none? { |e| e.include?('個は') },
      'unreachable' => final_errors.any? { |e| e.include?('つながらない') },
      'sub_guideline' => main_nodes && sub_guideline(main_nodes, difficulty),
      'reuse' => main_nodes ? reuse_stats(main_nodes) : {}
    }
  end

  # 構造化出力の方式を 1 回動かして，比べる項目を返す．
  def self.run_structured(client, goal, params, difficulty)
    attempts, result = MapPrototype.run(client, MapPrototype.request_body(goal, params), params, quiet: true)
    usage = attempts.map { |a| a['usage'] || {} }
    prompt = usage.sum { |u| u['promptTokenCount'].to_i }
    output = usage.sum { |u| u['candidatesTokenCount'].to_i + u['thoughtsTokenCount'].to_i }
    final_errors = result ? result['validation']['errors'] : ['パース失敗']
    # 最初のノードは，ノードが切り出せた最初の試行で測る（実装ではそのノードが保存・送信される）．
    first = attempts.index { |a| a['first_node_at'] }
    main_nodes = result && result['main_nodes']
    {
      'ok' => final_errors.empty?,
      'total_seconds' => (attempts.sum { |a| a['total_seconds'].to_f } - client.waited).round(2),
      'first_node_at' => first && (attempts[first]['first_node_at'] - client.waited(first)).round(2),
      'requests' => attempts.size,
      'prompt_tokens' => prompt,
      'output_tokens' => output,
      'yen' => yen(prompt, output),
      'rate_limit_wait' => client.waited,
      # 試行ごとの検証エラー．ノードを保存・送信した後に分かる誤りで，再生成が要る．
      'attempt_errors' => attempts.map { |a| a['errors'] || [a['error']] },
      'regenerations' => attempts.size - 1,
      'final_errors' => final_errors,
      'stats' => result && result['validation']['stats'],
      'main_nodes' => main_nodes
    }.merge(shape(main_nodes, final_errors, difficulty))
  end

  # ツール呼び出しの方式を 1 回動かして，比べる項目を返す．
  def self.run_tools(client, goal, params, difficulty)
    r = ToolPrototype.run(client, goal, params, quiet: true)
    prompt = r['usage']['promptTokenCount']
    output = r['usage']['candidatesTokenCount'] + r['usage']['thoughtsTokenCount']
    final_errors = r['finished'] ? r['validation']['errors'] : r['validation']['errors'] | ["終了: #{r['stop_reason']}"]
    {
      'ok' => final_errors.empty?,
      'stop_reason' => r['stop_reason'],
      'total_seconds' => (r['total_seconds'] - client.waited).round(2),
      'first_node_at' => r['first_node_at'] && (r['first_node_at'] - client.waited(r['first_node_turn'])).round(2),
      'requests' => r['turns'].size,
      'calls' => r['call_count'],
      'prompt_tokens' => prompt,
      'output_tokens' => output,
      'yen' => yen(prompt, output),
      'rate_limit_wait' => client.waited,
      # その場で返したエラー．呼び出しは反映されず，LLM が同じ生成の中で直す．
      'tool_errors' => r['tool_errors'].map { |e| "#{e['name']}: #{e['error']}" },
      'fixed_errors' => r['fixed_errors'],
      'finish_rejections' => r['finish_rejections'],
      'final_errors' => final_errors,
      'stats' => r['validation']['stats'],
      'turns' => r['turns'],
      'main_nodes' => r['main_nodes']
    }.merge(shape(r['main_nodes'], final_errors, difficulty))
  end

  # 中央値（0.1 単位）．
  def self.median(xs)
    s = xs.compact.sort
    return '-' if s.empty?

    m = s.size.odd? ? s[s.size / 2] : (s[s.size / 2 - 1] + s[s.size / 2]) / 2.0
    m.round(1)
  end

  # 中央値（最小〜最大）．
  def self.spread(xs)
    s = xs.compact
    return '-' if s.empty?

    "#{median(s)}（#{s.min.round(1)}〜#{s.max.round(1)}）"
  end

  # 方式 × 難易度の集計表（Markdown）．
  def self.table(rows)
    lines = [
      '| 方式 | 難易度 | 回数 | 検証エラーが残った | 全体（秒） | 最初のノード（秒） | 入力トークン | 出力トークン | 費用（円） | 往復 | 途中のエラー | 件数が範囲内 | ゴールへつながらない | サブノード数が目安内 | 既存サブノードの書き直し | 既存ノードの作り直し |',
      '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'
    ]
    %w[structured tools].each do |approach|
      %w[light standard deep].each do |difficulty|
        rs = rows.select { |r| r['approach'] == approach && r['difficulty'] == difficulty }
        next if rs.empty?

        done = rs.reject { |r| r['exception'] }
        mid =
          if approach == 'tools'
            "#{done.sum { |r| r['tool_errors'].size }} 回（直せた #{done.sum { |r| r['fixed_errors'] }}），finish の拒否 #{done.sum { |r| r['finish_rejections'] }}"
          else
            "再生成 #{done.sum { |r| r['regenerations'] }} 回"
          end
        guide = done.filter_map { |r| r['sub_guideline'] }
        guide_text = guide.empty? ? '-' : "#{(100.0 * guide.sum(&:first) / guide.sum(&:last)).round}%"
        lines << [
          approach == 'tools' ? 'ツール呼び出し' : '構造化出力', difficulty, rs.size,
          "#{rs.count { |r| !r['ok'] }}#{rs.any? { |r| r['exception'] } ? "（うち例外 #{rs.count { |r| r['exception'] }}）" : ''}",
          spread(done.map { |r| r['total_seconds'] }), spread(done.map { |r| r['first_node_at'] }),
          median(done.map { |r| r['prompt_tokens'] }), median(done.map { |r| r['output_tokens'] }),
          rs.sum { |r| r['yen'].to_f }.round(1),
          approach == 'tools' ? spread(done.map { |r| r['requests'] }) : '-',
          mid,
          "#{done.count { |r| r['count_in_range'] }}/#{done.size}",
          done.count { |r| r['unreachable'] },
          guide_text,
          done.sum { |r| r.dig('reuse', 'rewritten').to_i },
          done.sum { |r| (r.dig('reuse', 'recreated') || []).size }
        ].then { |cells| "| #{cells.join(' | ')} |" }
      end
    end
    lines.join("\n")
  end

  # ゴール × 難易度ごとに両方式を RUNS 回ずつ交互に動かし，結果を保存して表にする．
  def self.main(argv)
    if (i = argv.index('--table'))
      puts table(JSON.parse(File.read(argv[i + 1]))['rows'])
      return
    end
    dry_run = argv.delete('--dry-run')
    runs = Integer(ENV.fetch('RUNS', dry_run ? '1' : '3'))
    budget = Float(ENV.fetch('BUDGET_YEN', '900'))
    pause = Float(ENV.fetch('PAUSE_SECONDS', dry_run ? '0' : '5'))
    goals = ENV.fetch('GOALS', GOALS.keys.join(',')).split(',')
    difficulties = ENV.fetch('DIFFICULTIES', 'light,standard,deep').split(',')

    Dotenv.load
    model = ENV.fetch('GEMINI_MODEL', 'gemini-3.1-flash-lite')
    api_key = ENV['GEMINI_API_KEY'] or abort 'GEMINI_API_KEY が .env にない' unless dry_run
    rows = []
    spent = 0.0
    out_dir = File.join(__dir__, 'output')
    Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
    path = File.join(out_dir, "compare-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json")
    catch(:budget) do
      goals.each do |goal_key|
        goal = GOALS.fetch(goal_key)
        difficulties.each do |difficulty|
          params = MapPrototype::DIFFICULTY.fetch(difficulty)
          runs.times do |i|
            %w[structured tools].each do |approach|
              raw =
                if approach == 'structured'
                  dry_run ? MapPrototype::FakeStream.new : MapPrototype::GeminiStream.new(api_key: api_key, model: model)
                else
                  dry_run ? ToolPrototype::FakePartStream.new : ToolPrototype::GeminiPartStream.new(api_key: api_key, model: model)
                end
              client = RetryingClient.new(raw)
              begin
                row = approach == 'structured' ? run_structured(client, goal, params, difficulty) : run_tools(client, goal, params, difficulty)
              rescue StandardError => e
                # 費用が分からない失敗．件数は表の「例外」に出す．
                row = { 'ok' => false, 'exception' => "#{e.class}: #{e.message[0, 300]}", 'yen' => 0 }
              end
              row = { 'approach' => approach, 'goal' => goal_key, 'difficulty' => difficulty, 'run' => i + 1 }.merge(row)
              rows << row
              spent += row['yen'].to_f
              puts format('%-15s %-8s %-10s #%d ok=%-5s %6.1fs first=%6s req=%2s in=%7s out=%6s ¥%5.2f wait=%s %s',
                          goal_key, difficulty, approach, i + 1, row['ok'], row['total_seconds'].to_f, row['first_node_at'].inspect,
                          row['requests'].inspect, row['prompt_tokens'].inspect, row['output_tokens'].inspect, row['yen'].to_f,
                          row['rate_limit_wait'].inspect, row['exception'] || (row['final_errors'] || []).first(2).join(' / ')[0, 120])
              $stdout.flush
              File.write(path, JSON.pretty_generate({ 'model' => dry_run ? 'dry-run' : model, 'goals' => GOALS, 'spent_yen' => spent.round(2), 'rows' => rows }))
              throw :budget if spent > budget
              sleep pause
            end
          end
        end
      end
    end
    puts "合計 ¥#{spent.round(2)}"
    puts table(rows)
    puts "保存: #{path}"
  end
end

ComparePrototype.main(ARGV.dup) if $PROGRAM_NAME == __FILE__
