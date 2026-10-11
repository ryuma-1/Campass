# 0. BundlerでインストールしたGem（google-genaiやdotenv）をロードする設定（必須！）
require 'bundler/setup'

require 'google/genai'
# 1. dotenv ライブラリを追加
require 'dotenv'

# 2. クライアントを初期化する「前」に .env をロードする（超重要！）
Dotenv.load

# クライアントの初期化
client = Google::Genai::Client.new

puts "Geminiに送信する内容を入力してください:"
contents = gets.chomp

begin
  puts "Geminiにリクエストを送信中..."
  
  # コンテンツの生成
  response = client.models.generate_content(
    model: 'gemini-3.1-flash-lite',
    contents: contents,
    config: {
      temperature: 2 
    }
  )

  # 結果の出力
  puts "\n--- Geminiからの返答 ---"
  puts response.text
  puts "------------------------"

rescue Google::Genai::APIError => e
  puts "APIエラーが発生しました: #{e.message}"
rescue => e
  puts "予期せぬエラーが発生しました: #{e.message}"
end
