begin
  [1, 2].sort{|_a, _b| nil}
rescue => e
  p e.class
end
