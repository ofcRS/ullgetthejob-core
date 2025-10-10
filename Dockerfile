FROM elixir:1.15-alpine

RUN apk add --no-cache git

WORKDIR /app

COPY mix.exs mix.lock ./

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get && \
    mix deps.compile

COPY . .

RUN mix compile

EXPOSE 4000

CMD ["mix", "phx.server"]
