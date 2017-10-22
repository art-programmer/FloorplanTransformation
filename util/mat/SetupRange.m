function range = SetupRange(n,N,numIm)

if(~exist('numIm','var'))
    numIm = evalin('base','length(testFileList)');
end
size = numIm/N;
range = floor(1+(n-1)*size):floor(n*size);