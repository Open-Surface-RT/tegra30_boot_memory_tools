#!/bin/bash

# change these 3 filenames if needed
key=$(cat key.txt)
flash_image="flashImage.bin"
output_dir="./decrypted"

if [ ${#key} -ne 32 ]; then
	echo "Please provide a (valid) key in \"key.txt\""
	kill -INT $$
fi

if [ ! -f $flash_image ]; then
	echo "Please provide \"flashImage.bin\""
	kill -INT $$
fi

mkdir -p $output_dir

echo "Extract BCT/Bootloader from SPI flash"
dd if=$flash_image				of=$output_dir/BCT_Block_enc.bin		bs=1 count=8192                #extract the BCT block
dd if=$flash_image				of=$output_dir/Bootloader_Block_enc.bin	bs=1 count=520192 skip=1048576 #extract the Bootloader block
dd if=$output_dir/BCT_Block_enc.bin		of=$output_dir/BCT_enc.bin			bs=1 count=6128                #extract BCT from block
dd if=$output_dir/Bootloader_Block_enc.bin	of=$output_dir/Bootloader_enc.bin		bs=1 count=517472              #extract Bootloader from block
dd if=$output_dir/BCT_enc.bin			of=$output_dir/BCT_trimmed_enc.bin		bs=1 skip=16                   #extract BCT without hash
dd if=$output_dir/BCT_enc.bin			of=$output_dir/BCT_hash.bin			bs=1 count=16                  #extract BCT hash

echo ""
echo "decrypting Files"
openssl aes-128-cbc -d -K $key -iv 00000000000000000000000000000000 -nopad -nosalt -in $output_dir/BCT_enc.bin        -out $output_dir/BCT_dec.bin         #decrypt BCT
openssl aes-128-cbc -d -K $key -iv 00000000000000000000000000000000 -nopad -nosalt -in $output_dir/Bootloader_enc.bin -out $output_dir/Bootloader_dec.bin  #decrypt Bootloader

echo ""
echo "Extracted BCT hash"
xxd -ps $output_dir/BCT_hash.bin
echo "Calculated BCT hash"
openssl dgst -mac cmac -macopt cipher:aes-128-cbc -macopt hexkey:$key $output_dir/BCT_trimmed_enc.bin #hash of enc-BCT           #calc BCT hash

echo ""
echo "Extracted Bootloader hash:"
bct_dump $output_dir/BCT_dec.bin | grep AES
echo "Calculated Bootloader hash:"
openssl dgst -mac cmac -macopt cipher:aes-128-cbc -macopt hexkey:$key $output_dir/Bootloader_enc.bin #hash of enc-Bootloader     #calc Bootloader hash

echo ""
echo "remove temp files"
rm $output_dir/BCT_Block_enc.bin
rm $output_dir/BCT_enc.bin
rm $output_dir/BCT_trimmed_enc.bin
rm $output_dir/Bootloader_Block_enc.bin
rm $output_dir/Bootloader_enc.bin
