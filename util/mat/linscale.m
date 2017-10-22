function [ X ] = linscale( X, minV, maxV, low, high )
%SCALE Summary of this function goes here
%   Detailed explanation goes here

if ~exist('minV', 'var') && ~exist('maxV', 'var')
    minV = min(min(X));
    maxV = max(max(V));
end

if ~exist('low', 'var') && ~exist('high', 'var')
    low = 0;
    high = 1;
end

X = (high - low) * (X - minV) ./ (maxV - minV) + low;
X(X > high) = high;
X(X < low) = low;

end

