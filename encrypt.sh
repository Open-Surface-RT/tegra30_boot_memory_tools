#!/bin/bash
echo "Build SPI flashimage from BCT/Bootloader"
echo ""

# change these 3 filenames if needed
key=$(cat key.txt)
BCT="bct.bin"
Bootloader="bootloader.bin"
output_dir="./encrypted"

########## U-Boot ##############
# set bootloader load address
bootloaderLoadAddress=0x80108000
# set bootloader entry point
bootloaderEntryPoint=0x80108000 
########## U-Boot ##############

if [ ${#key} -ne 32 ]; then
	echo "Please provide a (valid) key in \"key.txt\""
	kill -INT $$
fi

if [ ! -f $BCT ]; then
	echo "Please provide \"bct.bin\""
	kill -INT $$
fi

if [ ! -f $Bootloader ]; then
	echo "Please provide \"bootloader.bin\""
	kill -INT $$
fi

mkdir -p $output_dir

cp $BCT $output_dir/tmp_bct.bin
cp $Bootloader $output_dir/tmp_bootloader.bin

###############################################################################
########### BOOTLOADER ########################################################
###############################################################################
# pad bootloader to be 16 Byte aligned
bootloaderLength=$(stat --printf="%s" $output_dir/tmp_bootloader.bin)
while [ $((bootloaderLength%16)) -ne 0 ]; do
	echo -n -e \\x00 >> $output_dir/tmp_bootloader.bin
	bootloaderLength=$(stat --printf="%s" $output_dir/tmp_bootloader.bin)
done

# encrypt bootloader
openssl aes-128-cbc -e -K $key -iv 00000000000000000000000000000000 -nopad -nosalt -in $output_dir/tmp_bootloader.bin -out $output_dir/tmp_bootloader_enc.bin

# calc hash of encrypted bootloader
bootloaderHash=$(openssl dgst -mac cmac -macopt cipher:aes-128-cbc -macopt hexkey:$key $output_dir/tmp_bootloader_enc.bin | cut -d' ' -f2)
# get length of encrypted bootloader
bootloaderLength=$(stat --printf="%s" $output_dir/tmp_bootloader_enc.bin)


# Swap endianess of Length, LoadAddress, EntryPoint
v=$(printf "%08x" $bootloaderLength)
bootloaderLength=${v:6:2}${v:4:2}${v:2:2}${v:0:2}
v=$(printf "%08x" $bootloaderLoadAddress)
bootloaderLoadAddress=${v:6:2}${v:4:2}${v:2:2}${v:0:2}
v=$(printf "%08x" $bootloaderEntryPoint)
bootloaderEntryPoint=${v:6:2}${v:4:2}${v:2:2}${v:0:2}

# add bootloader data to BCT
echo $bootloaderLoadAddress 	| xxd -r -p | dd conv=notrunc of=$output_dir/tmp_bct.bin seek=3940 bs=1
echo $bootloaderEntryPoint	| xxd -r -p | dd conv=notrunc of=$output_dir/tmp_bct.bin seek=3944 bs=1
echo $bootloaderHash		| xxd -r -p | dd conv=notrunc of=$output_dir/tmp_bct.bin seek=3952 bs=1
echo $bootloaderLength 	| xxd -r -p | dd conv=notrunc of=$output_dir/tmp_bct.bin seek=3936 bs=1

#create bootloader block count=0x7F000
dd if=/dev/zero of=$output_dir/tmp_bootloader_block.bin 						bs=1 count=520192
#put bootloader in block
dd conv=notrunc of=$output_dir/tmp_bootloader_block.bin if=$output_dir/tmp_bootloader_enc.bin 	bs=1


###############################################################################
########### BCT ###############################################################
###############################################################################
# remove HASH from BCT
dd if=$output_dir/tmp_bct.bin of=$output_dir/tmp_bct_trimmed.bin bs=1 skip=16

# encrypt BCT
openssl aes-128-cbc -e -K $key -iv 00000000000000000000000000000000 -nopad -nosalt -in $output_dir/tmp_bct_trimmed.bin -out $output_dir/tmp_bct_trimmed_enc.bin

# hash encrypted BCT
BCT_hash=$(openssl dgst -mac cmac -macopt cipher:aes-128-cbc -macopt hexkey:$key $output_dir/tmp_bct_trimmed_enc.bin | cut -d' ' -f2)

#create BCT_block image
dd if=/dev/zero of=$output_dir/tmp_bct_block.bin bs=1 count=8192  
#put hash in Image
echo $BCT_hash 		| xxd -r -p | dd conv=notrunc of=$output_dir/tmp_bct_block.bin seek=0 bs=1
#put BCT in Image
dd conv=notrunc if=$output_dir/tmp_bct_trimmed_enc.bin of=$output_dir/tmp_bct_block.bin seek=16 bs=1



###############################################################################
########### Flash Image########################################################
###############################################################################
# create spi flash image with ones/zeros
dd if=/dev/zero bs=512 count=8192 |   tr '\000' '\377' > flashImage.bin # to proof that dumped image is same as generated
#dd if=/dev/zero of=flashImage.bin bs=512 count=8192 # for flashing

#put BCT_Block in image
dd conv=notrunc if=$output_dir/tmp_bct_block.bin of=$output_dir/flashImage.bin seek=0 bs=1

#put Bootloader_block in image
dd conv=notrunc if=$output_dir/tmp_bootloader_block.bin of=$output_dir/flashImage.bin seek=1048576 bs=1



###############################################################################
########### Remove Tmp files ##################################################
###############################################################################
rm $output_dir/tmp_*.bin
