FROM ruby:4.0.5-slim

# Rails、MySQL、各種Gem（psych, mimemagic, nokogiri等）のビルド・動作に
# 必要なシステムパッケージを「まとめて」インストールします
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libmariadb-dev \
    libyaml-dev \
    shared-mime-info \
    pkg-config \
    tzdata \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app