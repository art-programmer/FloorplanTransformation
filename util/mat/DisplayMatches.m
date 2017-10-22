function DisplayMatches(HOMEDATA,K,fileList,index,rawNNs,imIn,imSP,spNums)
im = imIn;
numIm = 20;
for sp = spNums(:)'
    showSP(imIn,imSP,sp,0,1);
    showSP(imIn,imSP,sp,1,numIm+2);
    rawNN = rawNNs(sp);
    descs = fieldnames(rawNN);
    for Dndx = [ 8 14 ]%1:length(descs)1 3 4 16 17
        desc = descs{Dndx};
        nns = rawNN.(desc).nns;
        fprintf('%s: %d\n',desc,length(nns));
        for np = 0%:min(2,floor(length(nns)/numIm))
            for n = 1:min(numIm,length(nns)-(np*numIm))
                im = imread(fullfile(HOMEDATA,'..','Images',fileList{index.image(nns(n+(np*numIm)))}));

                [dirN base] = fileparts(fileList{index.image(nns(n+(np*numIm)))});
                baseFName = fullfile(dirN,base);
                outSPName = fullfile(HOMEDATA,'Descriptors',sprintf('SP_Desc_k%d',K),'super_pixels',sprintf('%s.mat',baseFName));
                load(outSPName);

                spNum = index.sp(nns(n));
                showSP(im,superPixels,spNum,0,n+1);
                showSP(im,superPixels,spNum,1,n+numIm+2);
                make_dir(fullfile('d:\tempsp',fileList{index.image(nns(n+(np*numIm)))}));copyfile(fullfile(HOMEDATA,'..','Images',fileList{index.image(nns(n+(np*numIm)))}),fullfile('d:\tempsp',fileList{index.image(nns(n+(np*numIm)))}));
                close(n+numIm+2);
            end
            for i = min(numIm,length(nns)-(np*numIm))+1:numIm
                im = zeros(size(im));
                show(im,i+1);
            end
            keyboard;
        end
    end
    
end
