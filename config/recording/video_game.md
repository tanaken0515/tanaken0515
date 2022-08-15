# ゲーム収録環境

## 2022-08-07..2022-08-14

### 電源供給

```mermaid
flowchart LR
  電源 --> Switch
  電源 --> 外部ディスプレイ
  電源 --> M1_MacBook_Air
  Switch -- USB給電 --> Proコン
  M1_MacBook_Air -- USB給電 --> HD60_S+
  M1_MacBook_Air -- USB給電 --> Blue_Yeti
```

### 操作入力と映像出力

```mermaid
flowchart LR
  hands[fa:fa-hands My Hands] --> Proコン 
  Proコン -- Bluetooth or USB --> Switch
  Switch -- HDMI --> HD60_S+
  HD60_S+  -- HDMI --> 外部ディスプレイ
  HD60_S+  -- USB --> M1_MacBook_Air
  subgraph M1_MacBook_Air
    subgraph OBS_Studio
      映像キャプチャデバイス --> スクリーン
    end
  end
  外部ディスプレイ --> eyes[fa:fa-eyes My Eyes]
```

### 音声入出力

```mermaid
flowchart LR
  Switch -- HDMI --> HD60_S+
  HD60_S+  -- HDMI --> 外部ディスプレイ
  HD60_S+  -- USB --> M1_MacBook_Air
  voice[fa:fa-waveform My Voice] --> Blue_Yeti
  Blue_Yeti  -- USB --> M1_MacBook_Air

  HD60_S+ -.-> Switch音声
  Blue_Yeti -.-> 外部マイク音声

  subgraph M1_MacBook_Air
    Switch音声 --> 入力2
    外部マイク音声

    subgraph BlackHole
      BlackHole_2ch
    end

    subgraph LadioCast
      入力2 --> 出力Aux1
      出力Aux1 --> BlackHole_2ch
    end

    外部マイク音声 --> マイク
    subgraph OBS_Studio
      マイク
      BlackHole_2ch --> デスクトップ音声
    end
  end
  
  外部ディスプレイ --> ears[fa:fa-ear My Ears]
```

## 2022-08-15..

電源供給と映像出力については変更なし。

### 音声入出力

音声通話アプリの出力も同時に収録できるように構成を変更した。

```mermaid
flowchart LR
  voice[fa:fa-waveform My Voice]
  Blue_Yeti
  Switch
  HD60_S+
  Aeropex
  外部ディスプレイ
  ears[fa:fa-ear My Ears]
  
  Switch -- HDMI --> HD60_S+
  HD60_S+ -- HDMI --> 外部ディスプレイ
  voice --> Blue_Yeti

  HD60_S+ --> Switch音声
  Blue_Yeti --> 外部マイク音声

  subgraph M1_MacBook_Air
    Switch音声
    外部マイク音声

    subgraph Mac環境設定
      入力装置 x-.-x 出力装置
    end

    subgraph 音声通話アプリ
      入力デバイス x-.-x 出力デバイス
    end

    subgraph BlackHole
      BlackHole_2ch
      BlackHole_16ch
      BlackHole_64ch
    end

    subgraph LadioCast
      入力1
      入力2
      入力3
      メイン出力
      出力Aux1
      出力Aux2
    end

    subgraph OBS_Studio
      マイク
      音声出力キャプチャ
    end
    
    出力装置 --> BlackHole_2ch --> 入力1 x-.-x メイン出力
    
    外部マイク音声 --> 入力デバイス
    外部マイク音声 --> マイク
    
    出力デバイス --> BlackHole_16ch --> 入力2
    入力2 --> 出力Aux1 --> BlackHole_64ch
    入力2 --> 出力Aux2

    Switch音声 --> 入力3 --> 出力Aux1
    
    BlackHole_64ch --> 音声出力キャプチャ
end
  
  外部ディスプレイ --> ears
  出力Aux2 --> Aeropex --> ears
```
