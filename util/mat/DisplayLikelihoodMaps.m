function DisplayLikelihoodMaps(probPerLabel,imSP,Labels,folder)

lmax = max(probPerLabel,[],1);
[foo lndx] = sort(lmax,'descend');
lndx = lndx(1:15);
lmax = 20;%max(max(probPerLabel(:,lndx),[],1));
lmin = -10;%min(min(probPerLabel(:,lndx),[],1));

if(~exist('folder','var'))
    folder = 'D:\tempsp\lmaps';
end

make_dir(fullfile(folder,'dum.dum'));
fid = fopen(fullfile(folder,'index.html'),'w');

numSteps = 256;
cmap = jet(numSteps);

for l = lndx(:)'
    prob = probPerLabel(:,l);
    probIm = prob(imSP);
    probIm = min(1,max(0,(probIm-lmin)./(lmax-lmin)));
    probIm3 = zeros([size(probIm) 3]);
    for c = 1:3
        map = cmap(:,c);
        probIm3(:,:,c) = map(max(1,ceil(probIm*numSteps)));
    end
    %probIm = repmat(probIm,[1 1 3]);
    show(probIm3,1);
    filename = sprintf('%s.png',Labels{l});
    imwrite(probIm3,fullfile(folder,filename));
    fprintf(fid,'<img src="%s"><br>%s<br><br>',filename,Labels{l});
end
fclose(fid);
