function [str] = myN2S(num,prec)
if(~exist('prec','var'))
    prec = 2;
end
if(num<1)
    str = sprintf('%%.%df',prec);
    str = sprintf(str,num);
else
    str = sprintf('%%0%dd',prec);
    str = sprintf(str,num);
end
end