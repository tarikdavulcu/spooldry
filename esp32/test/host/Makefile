# Host-side firmware tests (no ESP32 needed). Usage: make -C esp32/test/host test
CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -Werror -Wshadow -Wconversion -Wno-sign-conversion -fsanitize=address,undefined -g
CORE := ../../SpoolDry/src/core
SRCS := $(CORE)/Protocol.cpp $(CORE)/DryerController.cpp
TESTS := test_main.cpp test_protocol.cpp test_controller.cpp

all: test golden

spooldry_tests: $(TESTS) $(SRCS) $(wildcard $(CORE)/*.h) DryerSim.h TestFramework.h
	$(CXX) $(CXXFLAGS) -o $@ $(TESTS) $(SRCS) -lm

golden_vectors: golden_vectors.cpp $(SRCS) $(wildcard $(CORE)/*.h)
	$(CXX) $(CXXFLAGS) -o $@ golden_vectors.cpp $(CORE)/Protocol.cpp -lm

test: spooldry_tests
	./spooldry_tests

golden: golden_vectors
	./golden_vectors ../../../protocol/golden-vectors-v1.json

clean:
	rm -f spooldry_tests golden_vectors

.PHONY: all test golden clean
