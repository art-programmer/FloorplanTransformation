function [ ] = mk_dir( folder )
%MAKE_DIR Summary of this function goes here
%   Detailed explanation goes here

if (isdir(folder) == 0)
    mkdir(folder);
end

end
