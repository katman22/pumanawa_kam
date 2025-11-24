# app/lib/jwt_token.rb
module JwtToken
  ALG = "HS256"

  def self.secret = ENV.fetch("JWT_SECRET") # <— use JWT_SECRET consistently

  def self.issue(payload, exp: 30.days)
    JWT.encode(payload.merge(exp: exp.from_now.to_i), secret, ALG)
  end

  def self.decode(token)
    body, = JWT.decode(token, secret, true, algorithm: ALG)
    body.with_indifferent_access
  end
end
