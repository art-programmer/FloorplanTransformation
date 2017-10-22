function [ dirList baseList] = FileList2DirList( fileList )
dirList = cell(size(fileList));
if(nargout>1)
    baseList = cell(size(fileList));
    for i = 1:length(fileList)
        [dirList{i} base ext] = fileparts(fileList{i});
        baseList{i} = [base ext];
    end
else
    for i = 1:length(fileList)
        [dirList{i}] = fileparts(fileList{i});
    end
end
end

