function [ ] = make_dir( filePath )
%MAKE_DIR Summary of this function goes here
%   Detailed explanation goes here

[dirPath fileName] = fileparts(filePath);
if(isdir(dirPath)==0)
    mkdir(dirPath);
end

end
