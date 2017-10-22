function [ funList ] = GetFunList( funDir )
%GETFUNLIST Summary of this function goes here
%   Detailed explanation goes here

fileList = dir(fullfile(funDir,'*.m'));

funList = cell(length(fileList),1);
for i = 1:length(fileList)
    [foo funList{i}] = fileparts(fileList(i).name);
end