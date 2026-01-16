#include <openvino/openvino.hpp>
#include <iostream>

int main() {
    try {
        // Initialize OpenVINO runtime
        ov::Core core;

        // Load a small IR model
        std::shared_ptr<ov::Model> model = core.read_model("/tmp/dummy_model/squeezenet1.1.xml");

        // Compile the model for CPU
        ov::CompiledModel compiled_model = core.compile_model(model, "CPU");

        // Create an infer request
        ov::InferRequest infer_request = compiled_model.create_infer_request();

        std::cout << "Successfully loaded and compiled model on CPU!" << std::endl;
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "OpenVINO inference test failed: " << e.what() << std::endl;
        return 1;
    }
}
