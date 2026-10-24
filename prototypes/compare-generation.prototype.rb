# PROTOTYPE — throwaway code. Not production. Do not merge into main.
#
# Runs the structured output approach (#20) and the tool calling approach (#26) on the same goal
# for light / standard / deep, and prints time, tokens, validation errors and reuse correctness.
#
# Usage (GEMINI_API_KEY in .env):
#   RUNS=3 ruby prototypes/compare-generation.prototype.rb "React で Todo アプリを作れるようになる"
#   ruby prototypes/compare-generation.prototype.rb --dry-run
#
# Cost is estimated from usageMetadata at gemini-3.1-flash-lite prices and 155 JPY/USD.
# Thinking tokens are billed as output. The run stops once the estimate passes BUDGET_YEN (default 900).

require_relative 'llm-tool-calling.prototype'

# 2 つの方式を比べる．
module ComparePrototype
  USD_PER_M_INPUT = 0.25
  USD_PER_M_OUTPUT = 1.50
  JPY_PER_USD = 155

  # usageMetadata の合計から費用（円）を見積もる．
  def self.yen(prompt, output)
    ((prompt * USD_PER_M_INPUT + output * USD_PER_M_OUTPUT) / 1_000_000 * JPY_PER_USD).round(2)
  end

  # 再利用の正しさを数える．どちらの方式も #20 の出力の形（main_nodes）で数える．
  # rewritten: 再利用ノードの既存サブノードを書き直した数（許すが，無駄な出力）．
  # duplicated: 既存ノードと同じタイトルの新規ノード（再利用すべきだった）．
  def self.reuse_stats(main_nodes)
    existing = MapPrototype::EXISTING_NODES.to_h { |n| [n['id'], n] }
    titles = MapPrototype::EXISTING_NODES.to_h { |n| [norm(n['title']), n['id']] }
    stats = { 'reused' => 0, 'rewritten' => 0, 'duplicated' => [] }
    walk = lambda do |nodes, parent|
      nodes.each do |n|
        if n['existing_node_id']
          stats['reused'] += 1
          stats['rewritten'] += 1 if parent && (existing.dig(parent['existing_node_id'], 'sub_node_ids') || []).include?(n['existing_node_id'])
        elsif titles.key?(norm(n['title']))
          stats['duplicated'] << n['title']
        end
        walk.call(n['sub_nodes'] || [], n)
      end
    end
    walk.call(main_nodes, nil)
    stats
  end

  # 空白と大文字小文字の違いを無視して比べる．
  def self.norm(s)
    s.to_s.downcase.gsub(/\s+/, '')
  end

  # 構造化出力の方式を 1 回動かして，比べる項目を返す．
  def self.structured(client, goal, params)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    attempts, result = MapPrototype.run(client, MapPrototype.request_body(goal, params), params, quiet: true)
    usage = attempts.map { |a| a['usage'] || {} }
    prompt = usage.sum { |u| u['promptTokenCount'].to_i }
    output = usage.sum { |u| u['candidatesTokenCount'].to_i + u['thoughtsTokenCount'].to_i }
    final = result ? result['validation'] : { 'errors' => ['パース失敗'], 'stats' => {} }
    {
      'approach' => 'structured',
      'ok' => final['errors'].empty?,
      'total_seconds' => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2),
      'first_node_at' => attempts.first['first_node_at'],
      'requests' => attempts.size,
      'prompt_tokens' => prompt,
      'output_tokens' => output,
      'yen' => yen(prompt, output),
      # 最初の試行の検証エラー．ノードを保存・送信した後に分かる誤りで，再生成が要る．
      'first_errors' => attempts.first['errors'] || [attempts.first['error']],
      'retries' => attempts.size - 1,
      'final_errors' => final['errors'],
      'stats' => final['stats'],
      'reuse' => result ? reuse_stats(result['main_nodes']) : {},
      'main_nodes' => result && result['main_nodes']
    }
  end

  # ツール呼び出しの方式を 1 回動かして，比べる項目を返す．
  def self.tools(client, goal, params)
    r = ToolPrototype.run(client, goal, params, quiet: true)
    prompt = r['usage']['promptTokenCount']
    output = r['usage']['candidatesTokenCount'] + r['usage']['thoughtsTokenCount']
    {
      'approach' => 'tools',
      'ok' => r['finished'] && r['validation']['errors'].empty?,
      'stop_reason' => r['stop_reason'],
      'total_seconds' => r['total_seconds'],
      'first_node_at' => r['first_node_at'],
      'requests' => r['turns'].size,
      'calls' => r['call_count'],
      'prompt_tokens' => prompt,
      'output_tokens' => output,
      'yen' => yen(prompt, output),
      # その場で返したエラー．呼び出しは反映されず，LLM が同じ生成の中で直す．
      'tool_errors' => r['tool_errors'].map { |e| "#{e['name']}: #{e['error']}" },
      'finish_rejections' => r['finish_rejections'],
      'final_errors' => r['validation']['errors'],
      'stats' => r['validation']['stats'],
      'reuse' => reuse_stats(r['main_nodes']).merge('ignored_notes' => r['tool_notes'].size),
      'turns' => r['turns'],
      'main_nodes' => r['main_nodes']
    }
  end

  # 難易度ごとに両方式を RUNS 回ずつ交互に動かし，結果を保存して表にする．
  def self.main(argv)
    dry_run = argv.delete('--dry-run')
    goal = argv[0] || 'React で Todo アプリを作れるようになる'
    runs = Integer(ENV.fetch('RUNS', dry_run ? '1' : '3'))
    budget = Float(ENV.fetch('BUDGET_YEN', '900'))
    difficulties = ENV.fetch('DIFFICULTIES', 'light,standard,deep').split(',')

    Dotenv.load
    model = ENV.fetch('GEMINI_MODEL', 'gemini-3.1-flash-lite')
    api_key = ENV['GEMINI_API_KEY'] or abort 'GEMINI_API_KEY が .env にない' unless dry_run
    rows = []
    spent = 0.0
    catch(:budget) do
      difficulties.each do |difficulty|
        params = MapPrototype::DIFFICULTY.fetch(difficulty)
        runs.times do |i|
          {
            'structured' => -> { structured(dry_run ? MapPrototype::FakeStream.new : MapPrototype::GeminiStream.new(api_key: api_key, model: model), goal, params) },
            'tools' => -> { tools(dry_run ? ToolPrototype::FakePartStream.new : ToolPrototype::GeminiPartStream.new(api_key: api_key, model: model), goal, params) }
          }.each do |approach, run|
            begin
              row = run.call
            rescue StandardError => e
              row = { 'approach' => approach, 'ok' => false, 'exception' => "#{e.class}: #{e.message[0, 300]}", 'yen' => 0 }
            end
            row = row.merge('difficulty' => difficulty, 'run' => i + 1)
            rows << row
            spent += row['yen'].to_f
            puts format('%-8s %-10s #%d ok=%-5s %6.1fs first=%5s req=%2s in=%6s out=%5s ¥%5.2f  %s',
                        difficulty, approach, i + 1, row['ok'], row['total_seconds'].to_f, row['first_node_at'].inspect,
                        row['requests'].inspect, row['prompt_tokens'].inspect, row['output_tokens'].inspect, row['yen'].to_f,
                        row['exception'] || (row['final_errors'] || []).first(2).join(' / '))
            throw :budget if spent > budget
          end
        end
      end
    end
    puts "合計 ¥#{spent.round(2)}"

    out_dir = File.join(__dir__, 'output')
    Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
    path = File.join(out_dir, "compare-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json")
    File.write(path, JSON.pretty_generate({ 'goal' => goal, 'model' => dry_run ? 'dry-run' : model, 'spent_yen' => spent.round(2), 'rows' => rows }))
    puts "保存: #{path}"
  end
end

ComparePrototype.main(ARGV.dup) if $PROGRAM_NAME == __FILE__
