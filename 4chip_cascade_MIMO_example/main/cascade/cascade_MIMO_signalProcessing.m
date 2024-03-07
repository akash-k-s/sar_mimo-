%  Copyright (C) 2018 Texas Instruments Incorporated - http://www.ti.com/
%
%
%   Redistribution and use in source and binary forms, with or without
%   modification, are permitted provided that the following conditions
%   are met:
%
%     Redistributions of source code must retain the above copyright
%     notice, this list of conditions and the following disclaimer.
%
%     Redistributions in binary form must reproduce the above copyright
%     notice, this list of conditions and the following disclaimer in the
%     documentation and/or other materials provided with the
%     distribution.
%
%     Neither the name of Texas Instruments Incorporated nor the names of
%     its contributors may be used to endorse or promote products derived
%     from this software without specific prior written permission.
%
%   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
%   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
%   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
%   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
%   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
%   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
%   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%
%

% cascade_MIMO_signalProcessing.m
%
% Top level main test chain to process the raw ADC data. The processing
% chain including adc data calibration module, range FFT module, DopplerFFT
% module, CFAR module, DOA module. Each module is first initialized before
% actually used in the chain.
close all
clear all
clear vars
PARAM_FILE_GEN_ON = 1;
dataPlatform = 'TDA2'

%% get the input path and testList
pro_path = getenv('CASCADE_SIGNAL_PROCESSING_CHAIN_MIMO_1');
input_path = strcat(pro_path,'main\cascade\input\');
testList = strcat(input_path,'testList.txt');
%path for input folder
fidList = fopen(testList,'r');
testID = 1;
while ~feof(fidList)
    
    %% get each test vectors within the test list
    % test data file name
    dataFolder_test = fgetl(fidList);    
   
    %calibration file name
    dataFolder_calib = fgetl(fidList);
    
    %module_param_file defines parameters to init each signal processing
    %module
    module_param_file = fgetl(fidList);
    
     %parameter file name for the test
    pathGenParaFile = [input_path,'test',num2str(testID), '_param.m'];
    %important to clear the same.m file, since Matlab does not clear cache
    %automatically
    clear(pathGenParaFile);
    
    %generate parameter file for the test to run
    if PARAM_FILE_GEN_ON == 1     
        parameter_file_gen_json1(dataFolder_test, dataFolder_calib, module_param_file, pathGenParaFile, dataPlatform);
    end
    
    %load calibration parameters
    load(dataFolder_calib)
    
    % simTopObj is used for top level parameter parsing and data loading and saving
    simTopObj           = simTopCascade('pfile', pathGenParaFile);
    calibrationObj      = calibrationCascade('pfile', pathGenParaFile, 'calibrationfilePath', dataFolder_calib);
    
    % get system level variables
    platform            = simTopObj.platform;
    numValidFrames      = simTopObj.totNumFrames;
    cnt = 1;
    frameCountGlobal = 0;

   % Get Unique File Idxs in the "dataFolder_test" such as 0000, 0001, ...   
   [fileIdx_unique] = getUniqueFileIdx(dataFolder_test);
    
    for i_file = 1:(length(fileIdx_unique))
        
       % Get File Names for the Master, Slave1, Slave2, Slave3 and folder_name
       [fileNameStruct]= getBinFileNames_withIdx(dataFolder_test, fileIdx_unique{i_file});        
       
      %pass the Data File to the calibration Object
      calibrationObj.binfilePath = fileNameStruct;
       
        
       % Get Valid Number of Frames and datafilesize of master_xxxx_data.bin
       [numValidFrames dataFileSize] = getValidNumFrames(fullfile(dataFolder_test, fileNameStruct.masterIdxFile));
        %intentionally skip the first frame due to TDA2 
       
        for frameIdx = 2:1:numValidFrames;%numFrames_toRun
            %read and calibrate raw ADC data            
            calibrationObj.frameIdx = frameIdx;
            frameCountGlobal = frameCountGlobal+1;
            adcData = datapath(calibrationObj);
            
            % RX Channel re-ordering
            adcData = adcData(:,:,calibrationObj.RxForMIMOProcess,:);
            adcData_1 (:,:,:,:,(frameIdx-1)) = adcData(:,:,:,:); % adding frames to adc data
        end
        % rawdata_rxchain = num of adc samples * num of chirps * num of Rx * num of Tx * num of frames * num of measurments  
        rawData_rxchain(:,:,:,:,:,(i_file)) = adcData_1(:,:,:,:,:); %adding individual measurement to adc data
    end
end
clear adcData_1
clear adcData
size(rawData_rxchain);
% reshape the rawData_Rxchain as Num_RX_channels x Num_TX x Samples_per_Chirp x Chirps_per_Frame x Num_Frames x Num_measurements
rawData_rxchain = permute(rawData_rxchain,[3,4,1,2,5,6]);
x = size(rawData_rxchain);
chirp_per_frame = x(4);

Num_horizontalScan = 1;
Num_verticalScan = x(6);

%% Check the average chirps flag
if (chirp_per_frame > 1)
    averageChirps = true;
else
    averageChirps = false;
end
%% average over all chirps in a frame
if averageChirps
    rawData_rxchain = sum(rawData_rxchain,4)/chirp_per_frame; % Average Chirps( sums in chirp per frame dimension and divides) 
end
%% Reshape data
% rawData_rxchain = Num Tx* Num Rx, ADC samples, Num of frames , Num horizonal , Num vertical
rawData_rxchain = reshape(rawData_rxchain, x(1)*x(2),x(3),x(5),Num_horizontalScan,Num_verticalScan);

Num_horizontalScan = x(5);
rawData_rxchain = reshape(rawData_rxchain, x(1)*x(2),x(3),Num_horizontalScan,Num_verticalScan);
% rawData_rxchain = Num Tx* Num Rx, ADC samples, Num horizonal , Num vertical

%% For Continuous Scan - Crop the Data


%if (sarParams.Trigger_timeOffset_s < 0) % If Trigger is ahead of the scan
%    firstIndex = floor(abs(sarParams.Trigger_timeOffset_s) / (sensorParams.Frame_Repetition_Period_ms*1e-3)) + 1;
%    motionTime_s = calculateMotionDuration(sarParams.Horizontal_scanSize_mm,sarParams.Platform_Speed_mmps,200);
%    lastIndex = ceil(motionTime_s / (sensorParams.Frame_Repetition_Period_ms*1e-3)) + firstIndex;
%else
%    firstIndex = 1;
%    lastIndex = Num_horizontalScan; % Get all the samples
%    end

 %% Crop the Data
   % rawData = rawData(:,:,firstIndex:lastIndex,:);

 %% Define new Num_horizontalScan, rearrange the data
  %  [~,~,Num_horizontalScan,~] = size(rawData);
  %  sarParams.Num_horizontalScan = Num_horizontalScan;


 %% Rearrange the vertical scans
% This should be done for Rectangular Scan Mode
% rawData is (Num_RX * Num_TX) * Samples_per_Chirp * Num_horizontalScan * Num_verticalScan
for n = 1:Num_verticalScan
    if rem(n-1,2)
        rawData_rxchain(:,:,:,n) = flip(rawData_rxchain(:,:,:,n),3);
    end
end


%% Reshape the rawData
% Convert rawData to: (Num_RX * Num_TX) * Num_verticalScan * Num_horizontalScan * Samples_per_Chirp;
rawData_rxchain= permute(rawData_rxchain,[1,4,3,2]);

%% Beat Frequency Offset Calibration
%Slope_Hzpers = params.Slope_MHzperus*1e12;
%Sampling_Rate_sps = params.Sampling_Rate_sps;
%Samples_per_Chirp = calibrationObj.numSamplePerChirp;

%f = ((0:Samples_per_Chirp-1)*Slope_Hzpers/Sampling_Rate_sps); % wideband frequency
%f = reshape(f,1,1,1,[]);

%frequencyBiasFactor = exp(-1i*2*pi*delayOffset.*f);

%rawData_rxchain = rawData_rxchain .* frequencyBiasFactor;

%% Convert multistatic data to monostatic version
%--------------------------------------------------------------------------
frequency = [sensorParams.Start_Freq_GHz*1e9,Params.Slope_MHzperus*1e12,Params.Sampling_Rate_sps,sensorParams.Adc_Start_Time_us*1e-6];

% rawData format: (Num_RX * Num_TX) * Num_verticalScan * Num_horizontalScan * Samples_per_Chirp;
[~,rawDataMonostatic] = convertMultistaticToMonostatic(rawData_rxchain,frequency,xStepM_mm,yStepM_mm,zTarget_mm,'4ChipCascade',ones(1,Num_TX),ones(1,Num_RX));

