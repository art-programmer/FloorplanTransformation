function [ filePaths ] = dir_recurse( searchStr, includeSearchDir, recurse )
%DIR_RECURSE Summary of this function goes here
%   Detailed explanation goes here

if(~exist('includeSearchDir','var'))
    includeSearchDir=1;
end
if(~exist('recurse','var'))
    recurse=1;
end
[dirPath fileSearch ext] = fileparts(searchStr);
searchAll = fullfile(dirPath,'*');
if(~includeSearchDir)
    orgDir = pwd;
    cd(dirPath);
    dirPath = '';
    searchStr = [fileSearch ext];
    searchAll = '*';
end
if(recurse==0)
    searchAll = searchStr;
end
dirR = dir(searchStr);
rmndx = []; for i = 1:length(dirR);if(dirR(i).isdir);rmndx = [rmndx i];end;end;dirR(rmndx) = [];
dirD = dir(searchAll);
rmndx = []; for i = 1:length(dirD);if(~dirD(i).isdir);rmndx = [rmndx i];end;end;dirD(rmndx) = [];
fileSearch = [fileSearch ext];
filePaths = cell(0);
includedDir = 0;
for i = 1:length(dirR)
    name = dirR(i).name;
    if(strcmp('.',name) || strcmp('..',name) || strcmp('.DS_Store',name))
        continue;
    end
    if(isempty(dirPath))
        filePaths{length(filePaths)+1} = name;
    else
        filePaths{length(filePaths)+1} = fullfile(dirPath,name);
    end
end
for i = 1:length(dirD)
    name = dirD(i).name;
    if(strcmp('.',name) || strcmp('..',name))
        continue;
    end
    if(recurse)
        if(isempty(dirPath))
            paths = dir_recurse(fullfile(name,fileSearch));
        else
            paths = dir_recurse(fullfile(dirPath,name,fileSearch));
        end
        filePaths(length(filePaths)+1:length(filePaths)+length(paths)) = paths;
    else
        if(isempty(dirPath))
            filePaths{length(filePaths)+1} = name;
        else
            filePaths{length(filePaths)+1} = fullfile(dirPath,name);
        end
    end
end
if(~includeSearchDir)
    cd(orgDir);
end
