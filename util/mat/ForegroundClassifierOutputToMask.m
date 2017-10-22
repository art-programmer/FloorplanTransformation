inputDir = fullfile(HOMEDATA,'ColorModel7','MRF-Pix-ColorMAP-FGonly','LabelsForgroundBK','MAPCM-ELS FS0.00 BK100 R400C1 BConst.5.1 CMIT3 CM600 S100 IS0.000 Pmet IPcon SL0.00fx Pix l0.50-05 GCF1 FgFix0 WbS0');
outputDir = fullfile(HOMEDATA,'ColorModelMasks','CM6 S100');

for i = 1:length(testFileList)
    [folder base ext] = fileparts(testFileList{i});
    load(fullfile(inputDir,folder,[base '.mat']));
    mask = L==2;
    outfile = fullfile(outputDir,folder,[base '.mat']);make_dir(outfile);
    save(outfile,'mask');
end
